USE AlgorithmContestDB;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_Judgement_OneEffective
    ON dbo.Judgement(submission_id)
    WHERE is_effective = 1;
GO

CREATE INDEX IX_Submission_ContestTeamProblemTime
    ON dbo.Submission(contest_id, team_id, problem_id, submitted_at)
    INCLUDE (submission_id, language_id, sequence_no, submission_status);
GO

CREATE INDEX IX_Judgement_SubmissionEffective
    ON dbo.Judgement(submission_id, is_effective)
    INCLUDE (result_code, score, runtime_ms, memory_kb, judged_at);
GO

CREATE INDEX IX_RejudgeBatch_Status
    ON dbo.RejudgeBatch(contest_id, batch_status, created_at);
GO

CREATE INDEX IX_Clarification_ContestStatus
    ON dbo.Clarification(contest_id, clarification_status, asked_at);
GO

CREATE TRIGGER dbo.trg_TeamMember_MaxThree
ON dbo.TeamMember
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
    (
        SELECT tm.team_id
        FROM dbo.TeamMember tm
        JOIN (SELECT DISTINCT team_id FROM inserted) i ON i.team_id = tm.team_id
        GROUP BY tm.team_id
        HAVING COUNT(*) > 3
    )
    BEGIN
        THROW 51001, N'每支参赛队伍最多只能有三名队员。', 1;
    END;
END;
GO

CREATE TRIGGER dbo.trg_Submission_Validate
ON dbo.Submission
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF CONVERT(INT, SESSION_CONTEXT(N'SeedMode')) = 1 RETURN;

    IF EXISTS
    (
        SELECT 1
        FROM inserted i
        JOIN dbo.Team t ON t.team_id = i.team_id
        WHERE t.contest_id <> i.contest_id
    )
        THROW 51002, N'提交记录中的队伍不属于指定竞赛。', 1;

    IF EXISTS
    (
        SELECT 1
        FROM inserted i
        LEFT JOIN dbo.ContestProblem cp
          ON cp.contest_id = i.contest_id AND cp.problem_id = i.problem_id
        WHERE cp.problem_id IS NULL
    )
        THROW 51003, N'提交的题目未加入该竞赛。', 1;

    IF EXISTS
    (
        SELECT 1
        FROM inserted i
        JOIN dbo.Contest c ON c.contest_id = i.contest_id
        WHERE c.contest_status NOT IN ('RUNNING','FROZEN')
           OR i.submitted_at < c.start_time
           OR i.submitted_at > c.end_time
    )
        THROW 51004, N'当前竞赛状态或提交时间不允许写入提交记录。', 1;
END;
GO

CREATE TRIGGER dbo.trg_Judgement_Validate
ON dbo.Judgement
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF CONVERT(INT, SESSION_CONTEXT(N'SeedMode')) = 1 RETURN;

    IF EXISTS
    (
        SELECT 1
        FROM inserted i
        JOIN dbo.Submission s ON s.submission_id = i.submission_id
        JOIN dbo.RejudgeBatch b ON b.batch_id = i.rejudge_batch_id
        WHERE b.contest_id <> s.contest_id
    )
        THROW 51005, N'重判批次与提交记录不属于同一竞赛。', 1;

    UPDATE s
       SET submission_status = 'JUDGED'
    FROM dbo.Submission s
    JOIN inserted i ON i.submission_id = s.submission_id
    WHERE i.is_effective = 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RegisterTeam
    @ContestId INT,
    @TeamCode VARCHAR(30),
    @TeamName NVARCHAR(100),
    @Institution NVARCHAR(200),
    @TeamId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;
    DECLARE @status VARCHAR(20);
    SELECT @status = contest_status
    FROM dbo.Contest WITH (UPDLOCK, HOLDLOCK)
    WHERE contest_id = @ContestId;

    IF @status IS NULL THROW 52001, N'竞赛不存在。', 1;
    IF @status NOT IN ('DRAFT','REGISTRATION')
        THROW 52002, N'当前竞赛不在报名阶段。', 1;
    IF NULLIF(LTRIM(RTRIM(@TeamCode)), '') IS NULL
        THROW 52003, N'队伍编号不能为空。', 1;

    INSERT dbo.Team(contest_id, team_code, team_name, institution, team_status)
    VALUES (@ContestId, @TeamCode, @TeamName, @Institution, 'ACTIVE');

    SET @TeamId = CONVERT(INT, SCOPE_IDENTITY());
    COMMIT TRANSACTION;

    SELECT @TeamId AS team_id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AddTeamMember
    @TeamId INT,
    @UserId INT,
    @MemberRole VARCHAR(20) = 'MEMBER'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;
    IF NOT EXISTS (SELECT 1 FROM dbo.Team WITH (UPDLOCK, HOLDLOCK) WHERE team_id = @TeamId)
        THROW 52004, N'队伍不存在。', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.UserAccount WHERE user_id = @UserId)
        THROW 52005, N'用户不存在。', 1;
    IF @MemberRole NOT IN ('CAPTAIN','MEMBER','COACH')
        THROW 52006, N'队员角色不合法。', 1;
    IF EXISTS (SELECT 1 FROM dbo.TeamMember WHERE team_id = @TeamId AND user_id = @UserId)
        THROW 52007, N'该用户已经加入队伍。', 1;
    IF @MemberRole = 'CAPTAIN' AND EXISTS (SELECT 1 FROM dbo.TeamMember WHERE team_id = @TeamId AND member_role = 'CAPTAIN')
        THROW 52008, N'一支队伍只能有一名队长。', 1;

    INSERT dbo.TeamMember(team_id, user_id, member_role)
    VALUES (@TeamId, @UserId, @MemberRole);
    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_SubmitAttempt
    @ContestId INT,
    @TeamId INT,
    @ProblemId INT,
    @LanguageId INT,
    @SubmittedAt DATETIME2(0),
    @SourceHash CHAR(64) = NULL,
    @SourceSize INT = NULL,
    @CreatedBy INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;
    DECLARE @status VARCHAR(20), @start DATETIME2(0), @finish DATETIME2(0), @next INT;

    SELECT @status = contest_status, @start = start_time, @finish = end_time
    FROM dbo.Contest WITH (UPDLOCK, HOLDLOCK)
    WHERE contest_id = @ContestId;

    IF @status IS NULL THROW 52010, N'竞赛不存在。', 1;
    IF @status NOT IN ('RUNNING','FROZEN')
        THROW 52011, N'竞赛当前不接受提交。', 1;
    IF @SubmittedAt < @start OR @SubmittedAt > @finish
        THROW 52012, N'提交时间不在竞赛时间范围内。', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Team WHERE team_id = @TeamId AND contest_id = @ContestId AND team_status = 'ACTIVE')
        THROW 52013, N'队伍未注册或当前不可参赛。', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.ContestProblem WHERE contest_id = @ContestId AND problem_id = @ProblemId)
        THROW 52014, N'题目未加入该竞赛。', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.ProgrammingLanguage WHERE language_id = @LanguageId AND is_enabled = 1)
        THROW 52015, N'编程语言不存在或已禁用。', 1;

    SELECT @next = ISNULL(MAX(sequence_no), 0) + 1
    FROM dbo.Submission WITH (UPDLOCK, HOLDLOCK)
    WHERE contest_id = @ContestId AND team_id = @TeamId;

    INSERT dbo.Submission(contest_id, team_id, problem_id, language_id, sequence_no, submitted_at, source_hash, source_size, submission_status, created_by)
    VALUES (@ContestId, @TeamId, @ProblemId, @LanguageId, @next, @SubmittedAt, @SourceHash, @SourceSize, 'QUEUED', @CreatedBy);

    DECLARE @SubmissionId BIGINT = CONVERT(BIGINT, SCOPE_IDENTITY());
    COMMIT TRANSACTION;
    SELECT @SubmissionId AS submission_id, @next AS sequence_no;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ApplyRejudgeBatch
    @ContestId INT,
    @ProblemId INT = NULL,
    @TeamId INT = NULL,
    @Reason NVARCHAR(500),
    @CreatedBy INT,
    @ForceFailure BIT = 0,
    @BatchId BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @batchCode VARCHAR(40) = CONCAT('RJ-', CONVERT(CHAR(8), GETDATE(), 112), '-', RIGHT(CONVERT(VARCHAR(20), ABS(CHECKSUM(NEWID()))), 6));

        INSERT dbo.RejudgeBatch(contest_id, batch_code, reason, batch_status, created_by)
        VALUES (@ContestId, @batchCode, @Reason, 'RUNNING', @CreatedBy);
        SET @BatchId = CONVERT(BIGINT, SCOPE_IDENTITY());

        SELECT s.submission_id, j.result_code, j.score, j.runtime_ms, j.memory_kb, j.judge_message, j.judged_by
        INTO #Targets
        FROM dbo.Submission s WITH (UPDLOCK, HOLDLOCK)
        JOIN dbo.Judgement j ON j.submission_id = s.submission_id AND j.is_effective = 1
        WHERE s.contest_id = @ContestId
          AND (@ProblemId IS NULL OR s.problem_id = @ProblemId)
          AND (@TeamId IS NULL OR s.team_id = @TeamId);

        IF NOT EXISTS (SELECT 1 FROM #Targets)
            THROW 52020, N'没有符合条件的有效评测结果。', 1;

        UPDATE j
           SET is_effective = 0
        FROM dbo.Judgement j
        JOIN #Targets t ON t.submission_id = j.submission_id
        WHERE j.is_effective = 1;

        INSERT dbo.Judgement(submission_id, result_code, score, runtime_ms, memory_kb, is_effective, rejudge_batch_id, judge_message, judged_by)
        SELECT submission_id, result_code, score, runtime_ms, memory_kb, 1, @BatchId,
               CONCAT(ISNULL(judge_message, N''), N' [rejudge batch ', @BatchId, N']'), judged_by
        FROM #Targets;

        IF @ForceFailure = 1
            THROW 52021, N'模拟重判失败，事务应整体回滚。', 1;

        UPDATE dbo.RejudgeBatch
           SET batch_status = 'APPLIED', applied_at = SYSUTCDATETIME()
        WHERE batch_id = @BatchId;

        COMMIT TRANSACTION;
        SELECT @BatchId AS batch_id, @batchCode AS batch_code, N'APPLIED' AS batch_status;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER VIEW dbo.vw_CurrentJudgement
AS
SELECT
    s.submission_id, s.contest_id, s.team_id, s.problem_id, s.language_id,
    s.sequence_no, s.submitted_at, s.submission_status,
    j.judgement_id, j.result_code, j.score, j.runtime_ms, j.memory_kb,
    j.judged_at, j.rejudge_batch_id, j.judge_message
FROM dbo.Submission s
LEFT JOIN dbo.Judgement j
  ON j.submission_id = s.submission_id
 AND j.is_effective = 1;
GO

CREATE OR ALTER VIEW dbo.vw_SubmissionHistory
AS
SELECT
    s.submission_id, c.contest_code, c.title AS contest_title,
    t.team_code, t.team_name, p.problem_code, p.title AS problem_title,
    l.language_code, l.display_name AS language_name,
    s.sequence_no, s.submitted_at, s.submission_status,
    j.judgement_id, j.result_code, j.score, j.runtime_ms, j.memory_kb,
    j.is_effective, j.judged_at, rb.batch_code, j.judge_message
FROM dbo.Submission s
JOIN dbo.Contest c ON c.contest_id = s.contest_id
JOIN dbo.Team t ON t.team_id = s.team_id
JOIN dbo.Problem p ON p.problem_id = s.problem_id
JOIN dbo.ProgrammingLanguage l ON l.language_id = s.language_id
LEFT JOIN dbo.Judgement j ON j.submission_id = s.submission_id
LEFT JOIN dbo.RejudgeBatch rb ON rb.batch_id = j.rejudge_batch_id;
GO

CREATE OR ALTER VIEW dbo.vw_PublicScoreboard
AS
WITH Visible AS
(
    SELECT v.*
    FROM dbo.vw_CurrentJudgement v
    JOIN dbo.Contest c ON c.contest_id = v.contest_id
    WHERE c.contest_status <> 'FROZEN'
       OR c.freeze_at IS NULL
       OR v.submitted_at <= c.freeze_at
),
ProblemFirst AS
(
    SELECT contest_id, team_id, problem_id,
           MIN(CASE WHEN result_code = 'AC' THEN submitted_at END) AS first_ac_at,
           MAX(CASE WHEN result_code = 'AC' THEN 1 ELSE 0 END) AS solved,
           MAX(score) AS best_score
    FROM Visible
    GROUP BY contest_id, team_id, problem_id
),
ICPCProblem AS
(
    SELECT pf.contest_id, pf.team_id, pf.problem_id, pf.solved,
           CASE WHEN pf.solved = 1 THEN
               DATEDIFF(MINUTE, c.start_time, pf.first_ac_at)
               + 20 * ISNULL(SUM(CASE WHEN v.result_code NOT IN ('AC','CE')
                                         AND v.submitted_at < pf.first_ac_at THEN 1 ELSE 0 END), 0)
                ELSE 0 END AS penalty,
           pf.first_ac_at
    FROM ProblemFirst pf
    JOIN dbo.Contest c ON c.contest_id = pf.contest_id
    LEFT JOIN Visible v
      ON v.contest_id = pf.contest_id AND v.team_id = pf.team_id AND v.problem_id = pf.problem_id
    GROUP BY pf.contest_id, pf.team_id, pf.problem_id, pf.solved, pf.first_ac_at, c.start_time
),
ICPCScore AS
(
    SELECT t.contest_id, t.team_id, t.team_code, t.team_name, c.scoring_mode,
           SUM(ISNULL(ip.solved,0)) AS solved_count,
           SUM(ISNULL(ip.penalty,0)) AS total_penalty,
           CAST(0 AS DECIMAL(12,2)) AS total_score,
           MAX(ip.first_ac_at) AS last_solved_at
    FROM dbo.Team t
    JOIN dbo.Contest c ON c.contest_id = t.contest_id
    LEFT JOIN ICPCProblem ip ON ip.contest_id = t.contest_id AND ip.team_id = t.team_id
    WHERE c.scoring_mode = 'ICPC'
    GROUP BY t.contest_id, t.team_id, t.team_code, t.team_name, c.scoring_mode
),
IOIProblem AS
(
    SELECT pf.contest_id, pf.team_id, pf.problem_id, pf.best_score,
           MIN(CASE WHEN v.score = pf.best_score THEN v.submitted_at END) AS best_at
    FROM ProblemFirst pf
    JOIN Visible v ON v.contest_id = pf.contest_id AND v.team_id = pf.team_id AND v.problem_id = pf.problem_id
    GROUP BY pf.contest_id, pf.team_id, pf.problem_id, pf.best_score
),
IOIScore AS
(
    SELECT t.contest_id, t.team_id, t.team_code, t.team_name, c.scoring_mode,
           CAST(0 AS INT) AS solved_count,
           0 AS total_penalty,
           SUM(ISNULL(io.best_score,0)) AS total_score,
           MAX(io.best_at) AS last_solved_at
    FROM dbo.Team t
    JOIN dbo.Contest c ON c.contest_id = t.contest_id
    LEFT JOIN IOIProblem io ON io.contest_id = t.contest_id AND io.team_id = t.team_id
    WHERE c.scoring_mode = 'IOI'
    GROUP BY t.contest_id, t.team_id, t.team_code, t.team_name, c.scoring_mode
),
AllScores AS
(
    SELECT * FROM ICPCScore
    UNION ALL
    SELECT * FROM IOIScore
)
SELECT contest_id, team_id, team_code, team_name, scoring_mode,
       solved_count, total_score, total_penalty, last_solved_at,
       RANK() OVER
       (
           PARTITION BY contest_id
           ORDER BY
             CASE WHEN scoring_mode = 'ICPC' THEN solved_count END DESC,
             CASE WHEN scoring_mode = 'ICPC' THEN total_penalty END ASC,
             CASE WHEN scoring_mode = 'IOI' THEN total_score END DESC,
             CASE WHEN scoring_mode = 'IOI' THEN total_penalty END ASC,
             last_solved_at ASC,
             team_name ASC
       ) AS rank_no
FROM AllScores;
GO

CREATE OR ALTER VIEW dbo.vw_JuryScoreboard
AS
WITH ProblemFirst AS
(
    SELECT contest_id, team_id, problem_id,
           MIN(CASE WHEN result_code = 'AC' THEN submitted_at END) AS first_ac_at,
           MAX(CASE WHEN result_code = 'AC' THEN 1 ELSE 0 END) AS solved,
           MAX(score) AS best_score
    FROM dbo.vw_CurrentJudgement
    GROUP BY contest_id, team_id, problem_id
),
ICPCProblem AS
(
    SELECT pf.contest_id, pf.team_id, pf.problem_id, pf.solved,
           CASE WHEN pf.solved = 1 THEN
               DATEDIFF(MINUTE, c.start_time, pf.first_ac_at)
               + 20 * ISNULL(SUM(CASE WHEN v.result_code NOT IN ('AC','CE')
                                         AND v.submitted_at < pf.first_ac_at THEN 1 ELSE 0 END), 0)
                ELSE 0 END AS penalty,
           pf.first_ac_at
    FROM ProblemFirst pf
    JOIN dbo.Contest c ON c.contest_id = pf.contest_id
    LEFT JOIN dbo.vw_CurrentJudgement v
      ON v.contest_id = pf.contest_id AND v.team_id = pf.team_id AND v.problem_id = pf.problem_id
    GROUP BY pf.contest_id, pf.team_id, pf.problem_id, pf.solved, pf.first_ac_at, c.start_time
),
ICPCScore AS
(
    SELECT t.contest_id, t.team_id, t.team_code, t.team_name, c.scoring_mode,
           SUM(ISNULL(ip.solved,0)) AS solved_count,
           SUM(ISNULL(ip.penalty,0)) AS total_penalty,
           CAST(0 AS DECIMAL(12,2)) AS total_score,
           MAX(ip.first_ac_at) AS last_solved_at
    FROM dbo.Team t
    JOIN dbo.Contest c ON c.contest_id = t.contest_id
    LEFT JOIN ICPCProblem ip ON ip.contest_id = t.contest_id AND ip.team_id = t.team_id
    WHERE c.scoring_mode = 'ICPC'
    GROUP BY t.contest_id, t.team_id, t.team_code, t.team_name, c.scoring_mode
),
IOIProblem AS
(
    SELECT pf.contest_id, pf.team_id, pf.problem_id, pf.best_score,
           MIN(CASE WHEN v.score = pf.best_score THEN v.submitted_at END) AS best_at
    FROM ProblemFirst pf
    JOIN dbo.vw_CurrentJudgement v ON v.contest_id = pf.contest_id AND v.team_id = pf.team_id AND v.problem_id = pf.problem_id
    GROUP BY pf.contest_id, pf.team_id, pf.problem_id, pf.best_score
),
IOIScore AS
(
    SELECT t.contest_id, t.team_id, t.team_code, t.team_name, c.scoring_mode,
           CAST(0 AS INT) AS solved_count,
           0 AS total_penalty,
           SUM(ISNULL(io.best_score,0)) AS total_score,
           MAX(io.best_at) AS last_solved_at
    FROM dbo.Team t
    JOIN dbo.Contest c ON c.contest_id = t.contest_id
    LEFT JOIN IOIProblem io ON io.contest_id = t.contest_id AND io.team_id = t.team_id
    WHERE c.scoring_mode = 'IOI'
    GROUP BY t.contest_id, t.team_id, t.team_code, t.team_name, c.scoring_mode
),
AllScores AS
(
    SELECT * FROM ICPCScore
    UNION ALL
    SELECT * FROM IOIScore
)
SELECT contest_id, team_id, team_code, team_name, scoring_mode,
       solved_count, total_score, total_penalty, last_solved_at,
       RANK() OVER
       (
           PARTITION BY contest_id
           ORDER BY
             CASE WHEN scoring_mode = 'ICPC' THEN solved_count END DESC,
             CASE WHEN scoring_mode = 'ICPC' THEN total_penalty END ASC,
             CASE WHEN scoring_mode = 'IOI' THEN total_score END DESC,
             CASE WHEN scoring_mode = 'IOI' THEN total_penalty END ASC,
             last_solved_at ASC,
             team_name ASC
       ) AS rank_no
FROM AllScores;
GO

CREATE OR ALTER VIEW dbo.vw_ProblemStatistics
AS
SELECT
    c.contest_code, p.problem_code, p.title,
    COUNT(v.submission_id) AS submission_count,
    SUM(CASE WHEN v.result_code = 'AC' THEN 1 ELSE 0 END) AS accepted_submission_count,
    CAST(100.0 * SUM(CASE WHEN v.result_code = 'AC' THEN 1 ELSE 0 END)
         / NULLIF(COUNT(v.submission_id),0) AS DECIMAL(6,2)) AS accepted_rate,
    AVG(CAST(v.score AS DECIMAL(10,2))) AS average_score,
    MIN(CASE WHEN v.result_code = 'AC' THEN v.submitted_at END) AS first_accepted_at
FROM dbo.ContestProblem cp
JOIN dbo.Contest c ON c.contest_id = cp.contest_id
JOIN dbo.Problem p ON p.problem_id = cp.problem_id
LEFT JOIN dbo.vw_CurrentJudgement v
  ON v.contest_id = cp.contest_id AND v.problem_id = cp.problem_id
GROUP BY c.contest_code, p.problem_code, p.title;
GO

CREATE OR ALTER VIEW dbo.vw_TeamPerformance
AS
SELECT
    c.contest_code, t.team_code, t.team_name,
    COUNT(v.submission_id) AS submission_count,
    SUM(CASE WHEN v.result_code = 'AC' THEN 1 ELSE 0 END) AS accepted_count,
    CAST(100.0 * SUM(CASE WHEN v.result_code = 'AC' THEN 1 ELSE 0 END)
         / NULLIF(COUNT(v.submission_id),0) AS DECIMAL(6,2)) AS accepted_rate,
    AVG(CAST(v.runtime_ms AS DECIMAL(12,2))) AS average_runtime_ms,
    COUNT(DISTINCT CASE WHEN v.result_code = 'AC' THEN v.problem_id END) AS solved_problem_count
FROM dbo.Team t
JOIN dbo.Contest c ON c.contest_id = t.contest_id
LEFT JOIN dbo.vw_CurrentJudgement v
  ON v.team_id = t.team_id
GROUP BY c.contest_code, t.team_code, t.team_name;
GO
