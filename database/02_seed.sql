USE AlgorithmContestDB;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
EXEC sys.sp_set_session_context @key = N'SeedMode', @value = 1;
GO

INSERT dbo.UserAccount(username, display_name, email, user_role)
VALUES
('alice','算法组长 Alice','alice@example.edu','CONTESTANT'),
('bob','算法选手 Bob','bob@example.edu','CONTESTANT'),
('carol','算法选手 Carol','carol@example.edu','CONTESTANT'),
('david','算法选手 David','david@example.edu','CONTESTANT'),
('erin','算法选手 Erin','erin@example.edu','CONTESTANT'),
('frank','算法选手 Frank','frank@example.edu','CONTESTANT'),
('grace','算法选手 Grace','grace@example.edu','CONTESTANT'),
('henry','算法选手 Henry','henry@example.edu','CONTESTANT'),
('iris','算法选手 Iris','iris@example.edu','CONTESTANT'),
('jack','算法选手 Jack','jack@example.edu','CONTESTANT'),
('kate','算法选手 Kate','kate@example.edu','CONTESTANT'),
('leo','算法选手 Leo','leo@example.edu','CONTESTANT'),
('coach_liu','刘老师','coach@example.edu','COACH'),
('judge_wang','王裁判','judge@example.edu','JUDGE'),
('admin','系统管理员','admin@example.edu','ADMIN');
GO

INSERT dbo.Contest(contest_code, title, scoring_mode, start_time, end_time, freeze_at, contest_status, description)
VALUES
('CAMPUS-ICPC-2026',N'2026 校园算法竞赛春季赛','ICPC','2026-10-01T09:00:00','2026-10-08T14:00:00','2026-10-07T09:00:00','FROZEN',N'用于演示 ICPC 罚时、封榜和解榜。'),
('CAMPUS-IOI-2026',N'2026 算法能力挑战赛','IOI','2026-09-01T09:00:00','2026-09-05T14:00:00',NULL,'ENDED',N'用于演示 IOI 部分分和最高分。'),
('WINTER-ICPC-2026',N'2026 冬季校队选拔赛','ICPC','2026-11-01T09:00:00','2026-11-01T14:00:00','2026-11-01T12:00:00','REGISTRATION',N'用于演示报名流程。');
GO

INSERT dbo.Problem(problem_code, title, topic, difficulty, statement_url)
VALUES
('A',N'序列重排','贪心',1,NULL),
('B',N'最短路径','图论',2,NULL),
('C',N'区间合并','排序',2,NULL),
('D',N'树上路径','树论',3,NULL),
('E',N'网络流分配','网络流',4,NULL),
('F',N'动态规划优化','动态规划',4,NULL),
('G',N'字符串匹配','字符串',3,NULL),
('H',N'几何凸包','计算几何',5,NULL),
('I',N'矩阵快速幂','数论',3,NULL),
('J',N'博弈论基础','博弈',3,NULL),
('K',N'最小生成树','图论',2,NULL),
('L',N'随机化算法','概率',5,NULL);
GO

INSERT dbo.ProgrammingLanguage(language_code, display_name, version)
VALUES
('cpp17',N'C++ 17','GCC 13.2'),
('java17',N'Java 17','OpenJDK 17'),
('python311',N'Python 3.11','CPython 3.11'),
('rust2021',N'Rust 2021','rustc 1.78');
GO

INSERT dbo.ContestProblem(contest_id, problem_id, problem_label, points, time_limit_ms, memory_limit_mb, display_order)
SELECT c.contest_id, p.problem_id, p.problem_code,
       CASE WHEN c.scoring_mode = 'IOI' THEN 100 ELSE 100 END,
       CASE WHEN p.difficulty >= 4 THEN 4000 ELSE 2000 END,
       512,
       ASCII(p.problem_code) - 64
FROM dbo.Contest c
JOIN dbo.Problem p ON p.problem_code <= CASE WHEN c.contest_code = 'WINTER-ICPC-2026' THEN 'F' ELSE 'H' END
WHERE c.contest_code IN ('CAMPUS-ICPC-2026','CAMPUS-IOI-2026','WINTER-ICPC-2026');
GO

INSERT dbo.Team(contest_id, team_code, team_name, institution, team_status)
VALUES
(1,'ICPC-01',N'递归不归队',N'计算机学院','ACTIVE'),
(1,'ICPC-02',N'边界条件队',N'软件学院','ACTIVE'),
(1,'ICPC-03',N'三人行队',N'数学学院','ACTIVE'),
(1,'ICPC-04',N'暴力出奇迹',N'计算机学院','ACTIVE'),
(1,'ICPC-05',N'指针与引用',N'软件学院','ACTIVE'),
(1,'ICPC-06',N'图论研究所',N'计算机学院','ACTIVE'),
(1,'ICPC-07',N'动态规划局',N'数学学院','ACTIVE'),
(1,'ICPC-08',N'随机化协会',N'人工智能学院','ACTIVE'),
(2,'IOI-01',N'满分幻想家',N'计算机学院','ACTIVE'),
(2,'IOI-02',N'部分分专家',N'软件学院','ACTIVE'),
(2,'IOI-03',N'时间复杂度',N'数学学院','ACTIVE'),
(2,'IOI-04',N'数据结构组',N'计算机学院','ACTIVE'),
(3,'WIN-01',N'冬季一队',N'计算机学院','ACTIVE'),
(3,'WIN-02',N'冬季二队',N'软件学院','ACTIVE');
GO

INSERT dbo.TeamMember(team_id, user_id, member_role)
VALUES
(1,1,'CAPTAIN'),(1,2,'MEMBER'),(1,3,'MEMBER'),
(2,4,'CAPTAIN'),(2,5,'MEMBER'),(2,6,'MEMBER'),
(3,7,'CAPTAIN'),(3,8,'MEMBER'),(3,9,'MEMBER'),
(4,10,'CAPTAIN'),(4,11,'MEMBER'),(4,12,'MEMBER'),
(5,1,'CAPTAIN'),(5,5,'MEMBER'),(5,9,'MEMBER'),
(6,2,'CAPTAIN'),(6,6,'MEMBER'),(6,10,'MEMBER'),
(7,3,'CAPTAIN'),(7,7,'MEMBER'),(7,11,'MEMBER'),
(8,4,'CAPTAIN'),(8,8,'MEMBER'),(8,12,'MEMBER'),
(9,1,'CAPTAIN'),(9,6,'MEMBER'),(9,11,'MEMBER'),
(10,2,'CAPTAIN'),(10,7,'MEMBER'),(10,12,'MEMBER'),
(11,3,'CAPTAIN'),(11,8,'MEMBER'),(11,10,'MEMBER'),
(12,4,'CAPTAIN'),(12,9,'MEMBER'),(12,11,'MEMBER'),
(13,5,'CAPTAIN'),(13,6,'MEMBER'),(13,7,'MEMBER'),
(14,8,'CAPTAIN'),(14,9,'MEMBER'),(14,10,'MEMBER');
GO

;WITH TeamProblems AS
(
    SELECT t.team_id, t.contest_id, cp.problem_id, cp.display_order,
           c.start_time, c.freeze_at, c.scoring_mode
    FROM dbo.Team t
    JOIN dbo.Contest c ON c.contest_id = t.contest_id
    JOIN dbo.ContestProblem cp ON cp.contest_id = t.contest_id
),
Attempts AS
(
    SELECT tp.*, a.attempt_no
    FROM TeamProblems tp
    CROSS JOIN (VALUES (1),(2)) a(attempt_no)
)
INSERT dbo.Submission(contest_id, team_id, problem_id, language_id, sequence_no, submitted_at, source_hash, source_size, submission_status, created_by)
SELECT contest_id, team_id, problem_id,
       ((display_order + team_id) % 4) + 1,
       ROW_NUMBER() OVER (PARTITION BY team_id ORDER BY display_order, attempt_no),
       CASE
         WHEN contest_status = 'FROZEN' AND (ROW_NUMBER() OVER (PARTITION BY team_id ORDER BY display_order, attempt_no) % 5 = 0)
           THEN DATEADD(MINUTE, 15, freeze_at)
         ELSE DATEADD(MINUTE,
                      display_order * 9 + attempt_no * 4 + (team_id % 5),
                      start_time)
       END,
       CONVERT(CHAR(64), HASHBYTES('SHA2_256', CONCAT('seed-', contest_id, '-', team_id, '-', problem_id, '-', attempt_no)), 2),
       2048 + display_order * 100,
       'JUDGED',
       14
FROM
(
    SELECT a.*, c.contest_status
    FROM Attempts a
    JOIN dbo.Contest c ON c.contest_id = a.contest_id
) q;
GO

INSERT dbo.Judgement(submission_id, result_code, score, runtime_ms, memory_kb, is_effective, judged_at, judge_message, judged_by)
SELECT
    s.submission_id,
    CASE
      WHEN c.scoring_mode = 'IOI' AND s.sequence_no % 4 = 1 THEN 'WA'
      WHEN s.sequence_no % 2 = 1 THEN 'WA'
      ELSE 'AC'
    END,
    CASE
      WHEN c.scoring_mode = 'IOI' THEN
          CASE WHEN s.sequence_no % 4 = 1 THEN 40 ELSE 60 + (s.sequence_no % 5) * 8 END
      WHEN s.sequence_no % 2 = 1 THEN 0 ELSE 100 END,
    80 + (s.problem_id * 17) + (s.team_id % 7) * 9,
    32000 + (s.problem_id * 1200),
    1,
    DATEADD(MINUTE, 3, s.submitted_at),
    CASE WHEN s.sequence_no % 2 = 1 THEN N'样例数据：答案错误' ELSE N'样例数据：通过' END,
    14
FROM dbo.Submission s
JOIN dbo.Contest c ON c.contest_id = s.contest_id;
GO

INSERT dbo.Clarification(contest_id, team_id, question_text, answer_text, visibility, clarification_status, asked_at, answered_at, answered_by)
VALUES
(1,1,N'题目 B 的边权是否可能为负数？',N'不可能，所有边权均为非负整数。','ALL','ANSWERED','2026-10-01T10:15:00','2026-10-01T10:25:00',14),
(1,2,N'封榜后是否还能继续提交？',N'可以提交，但公开榜单暂不更新。','ALL','ANSWERED','2026-10-07T09:30:00','2026-10-07T09:35:00',14),
(2,9,N'IOI 题目是否取最高分？',N'每道题取所有有效提交中的最高分。','TEAM','ANSWERED','2026-09-01T11:00:00','2026-09-01T11:08:00',14);
GO

EXEC sys.sp_set_session_context @key = N'SeedMode', @value = NULL;
GO
