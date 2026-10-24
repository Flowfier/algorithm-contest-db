USE AlgorithmContestDB;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @passed INT = 0, @failed INT = 0;

PRINT N'=== 1. 基础结构检查 ===';
IF OBJECT_ID(N'dbo.vw_PublicScoreboard', N'V') IS NOT NULL SET @passed += 1 ELSE SET @failed += 1;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Judgement_OneEffective') SET @passed += 1 ELSE SET @failed += 1;
IF OBJECT_ID(N'dbo.usp_ApplyRejudgeBatch', N'P') IS NOT NULL SET @passed += 1 ELSE SET @failed += 1;

PRINT N'=== 2. 队员数量约束 ===';
BEGIN TRY
    INSERT dbo.TeamMember(team_id, user_id, member_role) VALUES (1,13,'MEMBER');
    SET @failed += 1;
    DELETE dbo.TeamMember WHERE team_id = 1 AND user_id = 13;
END TRY
BEGIN CATCH
    PRINT N'通过：超过三名队员会被拒绝。';
    SET @passed += 1;
END CATCH;

PRINT N'=== 3. 非法直接提交约束 ===';
BEGIN TRY
    INSERT dbo.Submission(contest_id, team_id, problem_id, language_id, sequence_no, submitted_at, submission_status, created_by)
    VALUES (1,1,1,1,999,'2026-10-09T09:00:00','QUEUED',14);
    SET @failed += 1;
END TRY
BEGIN CATCH
    PRINT N'通过：竞赛结束后的直接提交会被拒绝。';
    SET @passed += 1;
END CATCH;

PRINT N'=== 4. 提交存储过程 ===';
DECLARE @newSubmission BIGINT;
BEGIN TRY
    EXEC dbo.usp_SubmitAttempt
        @ContestId=1, @TeamId=1, @ProblemId=1, @LanguageId=1,
        @SubmittedAt='2026-10-07T08:10:00', @SourceHash=NULL, @SourceSize=3000, @CreatedBy=1;
    SELECT @newSubmission = MAX(submission_id) FROM dbo.Submission WHERE contest_id=1 AND team_id=1;
    IF @newSubmission IS NOT NULL SET @passed += 1 ELSE SET @failed += 1;
END TRY
BEGIN CATCH
    PRINT ERROR_MESSAGE();
    SET @failed += 1;
END CATCH;

INSERT dbo.Judgement(submission_id, result_code, score, runtime_ms, memory_kb, is_effective, judged_by)
VALUES (@newSubmission, 'AC', 100, 120, 28000, 1, 14);

PRINT N'=== 5. 结束竞赛后调用提交存储过程应失败 ===';
BEGIN TRY
    EXEC dbo.usp_SubmitAttempt
        @ContestId=2, @TeamId=9, @ProblemId=1, @LanguageId=1,
        @SubmittedAt='2026-09-06T10:00:00', @CreatedBy=1;
    SET @failed += 1;
END TRY
BEGIN CATCH
    PRINT N'通过：结束竞赛不接受新提交。';
    SET @passed += 1;
END CATCH;

PRINT N'=== 6. 重判失败回滚 ===';
DECLARE @target BIGINT, @beforeJudgement BIGINT, @afterJudgement BIGINT, @batch BIGINT;
SELECT TOP (1) @target = s.submission_id, @beforeJudgement = j.judgement_id
FROM dbo.Submission s JOIN dbo.Judgement j ON j.submission_id=s.submission_id AND j.is_effective=1
WHERE s.contest_id=1 AND s.team_id=1 AND s.problem_id=1
ORDER BY s.submission_id;
BEGIN TRY
    EXEC dbo.usp_ApplyRejudgeBatch
        @ContestId=1, @ProblemId=1, @TeamId=1, @Reason=N'失败回滚测试',
        @CreatedBy=14, @ForceFailure=1, @BatchId=@batch OUTPUT;
    SET @failed += 1;
END TRY
BEGIN CATCH
    SELECT @afterJudgement = judgement_id FROM dbo.Judgement WHERE submission_id=@target AND is_effective=1;
    IF @afterJudgement = @beforeJudgement
    BEGIN
        PRINT N'通过：重判失败后旧结果仍然有效。';
        SET @passed += 1;
    END
    ELSE SET @failed += 1;
END CATCH;

PRINT N'=== 7. 重判成功并保留历史 ===';
BEGIN TRY
    EXEC dbo.usp_ApplyRejudgeBatch
        @ContestId=1, @ProblemId=1, @TeamId=1, @Reason=N'正式重判测试',
        @CreatedBy=14, @ForceFailure=0, @BatchId=@batch OUTPUT;
    IF EXISTS (SELECT 1 FROM dbo.Judgement WHERE submission_id=@target AND is_effective=1 AND rejudge_batch_id=@batch)
       AND (SELECT COUNT(*) FROM dbo.Judgement WHERE submission_id=@target) >= 2
    BEGIN
        PRINT N'通过：新结果生效且旧结果保留。';
        SET @passed += 1;
    END
    ELSE SET @failed += 1;
END TRY
BEGIN CATCH
    PRINT ERROR_MESSAGE();
    SET @failed += 1;
END CATCH;

PRINT N'=== 8. 双模式榜单检查 ===';
IF EXISTS (SELECT 1 FROM dbo.vw_PublicScoreboard WHERE scoring_mode='ICPC' AND rank_no IS NOT NULL) SET @passed += 1 ELSE SET @failed += 1;
IF EXISTS (SELECT 1 FROM dbo.vw_JuryScoreboard WHERE scoring_mode='IOI' AND total_score > 0) SET @passed += 1 ELSE SET @failed += 1;
IF EXISTS (SELECT 1 FROM dbo.vw_TeamPerformance WHERE submission_count > 0) SET @passed += 1 ELSE SET @failed += 1;
IF EXISTS (SELECT 1 FROM dbo.vw_ProblemStatistics WHERE submission_count > 0) SET @passed += 1 ELSE SET @failed += 1;

PRINT N'=== 9. 冻结榜差异检查 ===';
DECLARE @publicRows INT, @juryRows INT;
SELECT @publicRows = COUNT(*) FROM dbo.vw_PublicScoreboard WHERE contest_id=1 AND solved_count > 0;
SELECT @juryRows = COUNT(*) FROM dbo.vw_JuryScoreboard WHERE contest_id=1 AND solved_count > 0;
IF @juryRows >= @publicRows SET @passed += 1 ELSE SET @failed += 1;

SELECT @passed AS passed_tests, @failed AS failed_tests,
       CASE WHEN @failed = 0 THEN N'PASS' ELSE N'FAIL' END AS overall_result;
IF @failed > 0 THROW 53000, N'测试脚本存在失败项，请检查上面的输出。', 1;
GO
