USE AlgorithmContestDB;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

CREATE TABLE dbo.UserAccount
(
    user_id       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_UserAccount PRIMARY KEY,
    username      NVARCHAR(50) NOT NULL CONSTRAINT UQ_UserAccount_Username UNIQUE,
    display_name  NVARCHAR(100) NOT NULL,
    email         NVARCHAR(200) NULL CONSTRAINT UQ_UserAccount_Email UNIQUE,
    user_role     VARCHAR(20) NOT NULL CONSTRAINT CK_UserAccount_Role CHECK (user_role IN ('CONTESTANT','COACH','JUDGE','ADMIN')),
    created_at    DATETIME2(0) NOT NULL CONSTRAINT DF_UserAccount_CreatedAt DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE dbo.Contest
(
    contest_id       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Contest PRIMARY KEY,
    contest_code     VARCHAR(30) NOT NULL CONSTRAINT UQ_Contest_Code UNIQUE,
    title            NVARCHAR(200) NOT NULL,
    scoring_mode     VARCHAR(10) NOT NULL CONSTRAINT CK_Contest_ScoringMode CHECK (scoring_mode IN ('ICPC','IOI')),
    start_time       DATETIME2(0) NOT NULL,
    end_time         DATETIME2(0) NOT NULL,
    freeze_at        DATETIME2(0) NULL,
    contest_status   VARCHAR(20) NOT NULL CONSTRAINT CK_Contest_Status CHECK (contest_status IN ('DRAFT','REGISTRATION','RUNNING','FROZEN','ENDED','CANCELLED')),
    description      NVARCHAR(1000) NULL,
    created_at       DATETIME2(0) NOT NULL CONSTRAINT DF_Contest_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_Contest_TimeOrder CHECK (start_time < end_time),
    CONSTRAINT CK_Contest_FreezeTime CHECK (freeze_at IS NULL OR (freeze_at >= start_time AND freeze_at < end_time))
);
GO

CREATE TABLE dbo.Team
(
    team_id       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Team PRIMARY KEY,
    contest_id    INT NOT NULL,
    team_code     VARCHAR(30) NOT NULL,
    team_name     NVARCHAR(100) NOT NULL,
    institution   NVARCHAR(200) NOT NULL,
    team_status   VARCHAR(20) NOT NULL CONSTRAINT CK_Team_Status CHECK (team_status IN ('PENDING','ACTIVE','DISQUALIFIED','WITHDRAWN')),
    created_at    DATETIME2(0) NOT NULL CONSTRAINT DF_Team_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_Team_Contest FOREIGN KEY (contest_id) REFERENCES dbo.Contest(contest_id),
    CONSTRAINT UQ_Team_ContestCode UNIQUE (contest_id, team_code)
);
GO

CREATE TABLE dbo.TeamMember
(
    team_id       INT NOT NULL,
    user_id       INT NOT NULL,
    member_role   VARCHAR(20) NOT NULL CONSTRAINT CK_TeamMember_Role CHECK (member_role IN ('CAPTAIN','MEMBER','COACH')),
    joined_at     DATETIME2(0) NOT NULL CONSTRAINT DF_TeamMember_JoinedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_TeamMember PRIMARY KEY (team_id, user_id),
    CONSTRAINT FK_TeamMember_Team FOREIGN KEY (team_id) REFERENCES dbo.Team(team_id),
    CONSTRAINT FK_TeamMember_User FOREIGN KEY (user_id) REFERENCES dbo.UserAccount(user_id)
);
GO

CREATE TABLE dbo.Problem
(
    problem_id     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Problem PRIMARY KEY,
    problem_code   VARCHAR(20) NOT NULL CONSTRAINT UQ_Problem_Code UNIQUE,
    title          NVARCHAR(200) NOT NULL,
    topic          NVARCHAR(100) NULL,
    difficulty     TINYINT NOT NULL CONSTRAINT CK_Problem_Difficulty CHECK (difficulty BETWEEN 1 AND 5),
    statement_url  NVARCHAR(500) NULL,
    created_at     DATETIME2(0) NOT NULL CONSTRAINT DF_Problem_CreatedAt DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE dbo.ContestProblem
(
    contest_id       INT NOT NULL,
    problem_id       INT NOT NULL,
    problem_label    CHAR(1) NOT NULL,
    points           DECIMAL(8,2) NOT NULL CONSTRAINT DF_ContestProblem_Points DEFAULT (100),
    time_limit_ms    INT NOT NULL CONSTRAINT DF_ContestProblem_TimeLimit DEFAULT (2000),
    memory_limit_mb  INT NOT NULL CONSTRAINT DF_ContestProblem_MemoryLimit DEFAULT (512),
    display_order    INT NOT NULL,
    CONSTRAINT PK_ContestProblem PRIMARY KEY (contest_id, problem_id),
    CONSTRAINT UQ_ContestProblem_Label UNIQUE (contest_id, problem_label),
    CONSTRAINT UQ_ContestProblem_Order UNIQUE (contest_id, display_order),
    CONSTRAINT FK_ContestProblem_Contest FOREIGN KEY (contest_id) REFERENCES dbo.Contest(contest_id),
    CONSTRAINT FK_ContestProblem_Problem FOREIGN KEY (problem_id) REFERENCES dbo.Problem(problem_id),
    CONSTRAINT CK_ContestProblem_Points CHECK (points > 0),
    CONSTRAINT CK_ContestProblem_Limits CHECK (time_limit_ms > 0 AND memory_limit_mb > 0),
    CONSTRAINT CK_ContestProblem_Label CHECK (problem_label LIKE '[A-Z]')
);
GO

CREATE TABLE dbo.ProgrammingLanguage
(
    language_id    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProgrammingLanguage PRIMARY KEY,
    language_code  VARCHAR(30) NOT NULL CONSTRAINT UQ_ProgrammingLanguage_Code UNIQUE,
    display_name   NVARCHAR(100) NOT NULL,
    version        VARCHAR(30) NULL,
    is_enabled     BIT NOT NULL CONSTRAINT DF_ProgrammingLanguage_Enabled DEFAULT (1)
);
GO

CREATE TABLE dbo.Submission
(
    submission_id  BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Submission PRIMARY KEY,
    contest_id     INT NOT NULL,
    team_id        INT NOT NULL,
    problem_id     INT NOT NULL,
    language_id    INT NOT NULL,
    sequence_no    INT NOT NULL,
    submitted_at   DATETIME2(0) NOT NULL,
    source_hash    CHAR(64) NULL,
    source_size    INT NULL,
    submission_status VARCHAR(20) NOT NULL CONSTRAINT DF_Submission_Status DEFAULT ('PENDING'),
    created_by     INT NULL,
    created_at     DATETIME2(0) NOT NULL CONSTRAINT DF_Submission_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_Submission_Sequence UNIQUE (contest_id, team_id, sequence_no),
    CONSTRAINT FK_Submission_Contest FOREIGN KEY (contest_id) REFERENCES dbo.Contest(contest_id),
    CONSTRAINT FK_Submission_Team FOREIGN KEY (team_id) REFERENCES dbo.Team(team_id),
    CONSTRAINT FK_Submission_Problem FOREIGN KEY (problem_id) REFERENCES dbo.Problem(problem_id),
    CONSTRAINT FK_Submission_Language FOREIGN KEY (language_id) REFERENCES dbo.ProgrammingLanguage(language_id),
    CONSTRAINT FK_Submission_Creator FOREIGN KEY (created_by) REFERENCES dbo.UserAccount(user_id),
    CONSTRAINT CK_Submission_Sequence CHECK (sequence_no > 0),
    CONSTRAINT CK_Submission_SourceSize CHECK (source_size IS NULL OR source_size BETWEEN 1 AND 10485760),
    CONSTRAINT CK_Submission_Status CHECK (submission_status IN ('PENDING','QUEUED','JUDGED','CANCELLED'))
);
GO

CREATE TABLE dbo.RejudgeBatch
(
    batch_id       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RejudgeBatch PRIMARY KEY,
    contest_id     INT NOT NULL,
    batch_code     VARCHAR(40) NOT NULL CONSTRAINT UQ_RejudgeBatch_Code UNIQUE,
    reason         NVARCHAR(500) NOT NULL,
    batch_status   VARCHAR(20) NOT NULL CONSTRAINT DF_RejudgeBatch_Status DEFAULT ('DRAFT'),
    created_by     INT NOT NULL,
    created_at     DATETIME2(0) NOT NULL CONSTRAINT DF_RejudgeBatch_CreatedAt DEFAULT SYSUTCDATETIME(),
    applied_at     DATETIME2(0) NULL,
    CONSTRAINT FK_RejudgeBatch_Contest FOREIGN KEY (contest_id) REFERENCES dbo.Contest(contest_id),
    CONSTRAINT FK_RejudgeBatch_Creator FOREIGN KEY (created_by) REFERENCES dbo.UserAccount(user_id),
    CONSTRAINT CK_RejudgeBatch_Status CHECK (batch_status IN ('DRAFT','RUNNING','APPLIED','CANCELLED','FAILED'))
);
GO

CREATE TABLE dbo.Judgement
(
    judgement_id   BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Judgement PRIMARY KEY,
    submission_id  BIGINT NOT NULL,
    result_code    VARCHAR(10) NOT NULL,
    score          DECIMAL(8,2) NOT NULL CONSTRAINT DF_Judgement_Score DEFAULT (0),
    runtime_ms     INT NULL,
    memory_kb      INT NULL,
    is_effective   BIT NOT NULL CONSTRAINT DF_Judgement_Effective DEFAULT (0),
    judged_at      DATETIME2(0) NOT NULL CONSTRAINT DF_Judgement_JudgedAt DEFAULT SYSUTCDATETIME(),
    rejudge_batch_id BIGINT NULL,
    judge_message  NVARCHAR(500) NULL,
    judged_by      INT NULL,
    CONSTRAINT FK_Judgement_Submission FOREIGN KEY (submission_id) REFERENCES dbo.Submission(submission_id),
    CONSTRAINT FK_Judgement_RejudgeBatch FOREIGN KEY (rejudge_batch_id) REFERENCES dbo.RejudgeBatch(batch_id),
    CONSTRAINT FK_Judgement_Judge FOREIGN KEY (judged_by) REFERENCES dbo.UserAccount(user_id),
    CONSTRAINT CK_Judgement_Result CHECK (result_code IN ('PENDING','AC','WA','CE','TLE','RTE','MLE','RE')),
    CONSTRAINT CK_Judgement_Score CHECK (score BETWEEN 0 AND 100),
    CONSTRAINT CK_Judgement_Runtime CHECK (runtime_ms IS NULL OR runtime_ms >= 0),
    CONSTRAINT CK_Judgement_Memory CHECK (memory_kb IS NULL OR memory_kb >= 0)
);
GO

CREATE TABLE dbo.Clarification
(
    clarification_id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Clarification PRIMARY KEY,
    contest_id       INT NOT NULL,
    team_id          INT NULL,
    question_text    NVARCHAR(1000) NOT NULL,
    answer_text      NVARCHAR(2000) NULL,
    visibility       VARCHAR(10) NOT NULL CONSTRAINT DF_Clarification_Visibility DEFAULT ('ALL'),
    clarification_status VARCHAR(20) NOT NULL CONSTRAINT DF_Clarification_Status DEFAULT ('OPEN'),
    asked_at         DATETIME2(0) NOT NULL CONSTRAINT DF_Clarification_AskedAt DEFAULT SYSUTCDATETIME(),
    answered_at      DATETIME2(0) NULL,
    answered_by      INT NULL,
    CONSTRAINT FK_Clarification_Contest FOREIGN KEY (contest_id) REFERENCES dbo.Contest(contest_id),
    CONSTRAINT FK_Clarification_Team FOREIGN KEY (team_id) REFERENCES dbo.Team(team_id),
    CONSTRAINT FK_Clarification_Answerer FOREIGN KEY (answered_by) REFERENCES dbo.UserAccount(user_id),
    CONSTRAINT CK_Clarification_Visibility CHECK (visibility IN ('TEAM','ALL')),
    CONSTRAINT CK_Clarification_Status CHECK (clarification_status IN ('OPEN','ANSWERED','CLOSED'))
);
GO
