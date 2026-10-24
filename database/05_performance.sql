USE AlgorithmContestDB;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
PRINT N'=== 生成性能测试数据 ===';
EXEC sys.sp_set_session_context @key = N'SeedMode', @value = 1;
;WITH N AS
(
    SELECT TOP (2500) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
),
RowsToInsert AS
(
    SELECT
       2 AS contest_id,
       9 + ((n - 1) % 4) AS team_id,
       1 + ((n - 1) % 8) AS problem_id,
       1 + ((n - 1) % 4) AS language_id,
       16 + ROW_NUMBER() OVER (PARTITION BY (9 + ((n - 1) % 4)) ORDER BY n) AS sequence_no,
       DATEADD(SECOND, n, CONVERT(DATETIME2(0),'2026-09-01T09:00:00')) AS submitted_at,
       n
    FROM N
)
INSERT dbo.Submission(contest_id, team_id, problem_id, language_id, sequence_no, submitted_at, source_size, submission_status, created_by)
SELECT contest_id, team_id, problem_id, language_id,
       sequence_no, submitted_at, 4096, 'JUDGED', 14
FROM RowsToInsert;
GO
INSERT dbo.Judgement(submission_id, result_code, score, runtime_ms, memory_kb, is_effective, judged_by)
SELECT submission_id,
       CASE WHEN submission_id % 5 = 0 THEN 'AC' ELSE 'WA' END,
       CASE WHEN submission_id % 5 = 0 THEN 100 ELSE 0 END,
       100 + submission_id % 900, 20000 + submission_id % 40000, 1, 14
FROM dbo.Submission
WHERE contest_id = 2 AND submission_id NOT IN (SELECT submission_id FROM dbo.Judgement);
GO
EXEC sys.sp_set_session_context @key = N'SeedMode', @value = NULL;

PRINT N'=== 无索引基线 ===';
DROP INDEX IF EXISTS IX_Submission_ContestTeamProblemTime ON dbo.Submission;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SELECT s.contest_id, s.team_id, s.problem_id, COUNT(*) AS attempts, MAX(j.score) AS best_score
FROM dbo.Submission s
JOIN dbo.Judgement j ON j.submission_id=s.submission_id AND j.is_effective=1
WHERE s.contest_id=2 AND s.team_id=9 AND s.problem_id=1 AND s.submitted_at >= '2026-09-01T09:00:00'
GROUP BY s.contest_id, s.team_id, s.problem_id;
SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;

PRINT N'=== 创建复合覆盖索引后 ===';
CREATE INDEX IX_Submission_ContestTeamProblemTime
    ON dbo.Submission(contest_id, team_id, problem_id, submitted_at)
    INCLUDE (submission_id, language_id, sequence_no, submission_status);

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SELECT s.contest_id, s.team_id, s.problem_id, COUNT(*) AS attempts, MAX(j.score) AS best_score
FROM dbo.Submission s
JOIN dbo.Judgement j ON j.submission_id=s.submission_id AND j.is_effective=1
WHERE s.contest_id=2 AND s.team_id=9 AND s.problem_id=1 AND s.submitted_at >= '2026-09-01T09:00:00'
GROUP BY s.contest_id, s.team_id, s.problem_id;
SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
PRINT N'对比完成：请核对两次结果集及 logical reads、CPU time、elapsed time。';
GO
