using Microsoft.Data.SqlClient;
using Microsoft.AspNetCore.Diagnostics;
using System.Data;

var builder = WebApplication.CreateBuilder(args);
var connectionString = builder.Configuration.GetConnectionString("AlgorithmContestDb")
    ?? throw new InvalidOperationException("Missing connection string AlgorithmContestDb.");

var app = builder.Build();
app.UseExceptionHandler(errorApp => errorApp.Run(async context =>
{
    var feature = context.Features.Get<IExceptionHandlerFeature>();
    context.Response.StatusCode = StatusCodes.Status500InternalServerError;
    context.Response.ContentType = "application/json; charset=utf-8";
    await context.Response.WriteAsJsonAsync(new
    {
        error = "数据库请求失败，请检查 SQL Server 连接和数据库对象。",
        detail = feature?.Error.Message
    });
}));
app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/api/health", () => Results.Ok(new { status = "ok", service = "AlgorithmContestWeb" }));

app.MapGet("/api/contests", async () =>
{
    await using var conn = await Db.OpenAsync(connectionString);
    await using var cmd = new SqlCommand("""
        SELECT c.contest_id, c.contest_code, c.title, c.scoring_mode,
               c.start_time, c.end_time, c.freeze_at, c.contest_status,
               c.description,
               (SELECT COUNT(*) FROM dbo.Team t WHERE t.contest_id = c.contest_id) AS team_count,
               (SELECT COUNT(*) FROM dbo.ContestProblem cp WHERE cp.contest_id = c.contest_id) AS problem_count,
               (SELECT COUNT(*) FROM dbo.Submission s WHERE s.contest_id = c.contest_id) AS submission_count
        FROM dbo.Contest c
        ORDER BY c.start_time DESC;
        """, conn);

    var rows = new List<object>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(new
        {
            contestId = reader.GetInt32(0),
            contestCode = reader.GetString(1),
            title = reader.GetString(2),
            scoringMode = reader.GetString(3),
            startTime = reader.GetDateTime(4),
            endTime = reader.GetDateTime(5),
            freezeAt = Db.NullableDate(reader, 6),
            status = reader.GetString(7),
            description = Db.NullableString(reader, 8),
            teamCount = reader.GetInt32(9),
            problemCount = reader.GetInt32(10),
            submissionCount = reader.GetInt32(11)
        });
    }
    return Results.Ok(rows);
});

app.MapGet("/api/contests/{contestId:int}", async (int contestId) =>
{
    await using var conn = await Db.OpenAsync(connectionString);
    await using var contestCmd = new SqlCommand("""
        SELECT contest_id, contest_code, title, scoring_mode, start_time, end_time,
               freeze_at, contest_status, description
        FROM dbo.Contest WHERE contest_id = @contestId;
        """, conn);
    contestCmd.Parameters.Add("@contestId", SqlDbType.Int).Value = contestId;
    await using var contestReader = await contestCmd.ExecuteReaderAsync();
    if (!await contestReader.ReadAsync()) return Results.NotFound(new { error = "竞赛不存在" });
    var contest = new
    {
        contestId = contestReader.GetInt32(0),
        contestCode = contestReader.GetString(1),
        title = contestReader.GetString(2),
        scoringMode = contestReader.GetString(3),
        startTime = contestReader.GetDateTime(4),
        endTime = contestReader.GetDateTime(5),
        freezeAt = Db.NullableDate(contestReader, 6),
        status = contestReader.GetString(7),
        description = Db.NullableString(contestReader, 8)
    };
    await contestReader.CloseAsync();

    await using var problemCmd = new SqlCommand("""
        SELECT p.problem_id, cp.problem_label, p.problem_code, p.title, p.topic,
               p.difficulty, cp.points, cp.time_limit_ms, cp.memory_limit_mb
        FROM dbo.ContestProblem cp
        JOIN dbo.Problem p ON p.problem_id = cp.problem_id
        WHERE cp.contest_id = @contestId
        ORDER BY cp.display_order;
        """, conn);
    problemCmd.Parameters.Add("@contestId", SqlDbType.Int).Value = contestId;
    var problems = new List<object>();
    await using (var reader = await problemCmd.ExecuteReaderAsync())
    {
        while (await reader.ReadAsync())
        {
            problems.Add(new
            {
                problemId = reader.GetInt32(0),
                label = reader.GetString(1),
                problemCode = reader.GetString(2),
                title = reader.GetString(3),
                topic = Db.NullableString(reader, 4),
                difficulty = reader.GetByte(5),
                points = reader.GetDecimal(6),
                timeLimitMs = reader.GetInt32(7),
                memoryLimitMb = reader.GetInt32(8)
            });
        }
    }

    await using var teamCmd = new SqlCommand("""
        SELECT t.team_id, t.team_code, t.team_name, t.institution, t.team_status,
               COUNT(tm.user_id) AS member_count
        FROM dbo.Team t
        LEFT JOIN dbo.TeamMember tm ON tm.team_id = t.team_id
        WHERE t.contest_id = @contestId
        GROUP BY t.team_id, t.team_code, t.team_name, t.institution, t.team_status
        ORDER BY t.team_code;
        """, conn);
    teamCmd.Parameters.Add("@contestId", SqlDbType.Int).Value = contestId;
    var teams = new List<object>();
    await using (var reader = await teamCmd.ExecuteReaderAsync())
    {
        while (await reader.ReadAsync())
        {
            teams.Add(new
            {
                teamId = reader.GetInt32(0),
                teamCode = reader.GetString(1),
                teamName = reader.GetString(2),
                institution = reader.GetString(3),
                status = reader.GetString(4),
                memberCount = reader.GetInt32(5)
            });
        }
    }

    return Results.Ok(new { contest, problems, teams });
});

app.MapGet("/api/metrics/{contestId:int}", async (int contestId) =>
{
    await using var conn = await Db.OpenAsync(connectionString);
    await using var cmd = new SqlCommand("""
        SELECT
          (SELECT COUNT(*) FROM dbo.Team WHERE contest_id = @contestId) AS team_count,
          (SELECT COUNT(*) FROM dbo.ContestProblem WHERE contest_id = @contestId) AS problem_count,
          (SELECT COUNT(*) FROM dbo.Submission WHERE contest_id = @contestId) AS submission_count,
          (SELECT COUNT(*) FROM dbo.vw_CurrentJudgement WHERE contest_id = @contestId AND result_code = 'AC') AS accepted_count,
          (SELECT COUNT(DISTINCT team_id) FROM dbo.vw_CurrentJudgement WHERE contest_id = @contestId AND result_code = 'AC') AS solved_team_count,
          (SELECT COUNT(*) FROM dbo.Submission s JOIN dbo.Contest c ON c.contest_id = s.contest_id
             WHERE s.contest_id = @contestId AND c.contest_status = 'FROZEN' AND c.freeze_at IS NOT NULL
             AND s.submitted_at > c.freeze_at) AS hidden_submission_count;
        """, conn);
    cmd.Parameters.Add("@contestId", SqlDbType.Int).Value = contestId;
    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync()) return Results.NotFound();
    return Results.Ok(new
    {
        teams = reader.GetInt32(0),
        problems = reader.GetInt32(1),
        submissions = reader.GetInt32(2),
        accepted = reader.GetInt32(3),
        solvedTeams = reader.GetInt32(4),
        hiddenSubmissions = reader.GetInt32(5)
    });
});

app.MapGet("/api/scoreboard/{contestId:int}", async (int contestId, string? mode, string? visibility) =>
{
    if (!string.IsNullOrWhiteSpace(mode) && mode is not ("ICPC" or "IOI"))
        return Results.BadRequest(new { error = "mode 必须是 ICPC 或 IOI" });
    var isJury = string.Equals(visibility, "jury", StringComparison.OrdinalIgnoreCase);
    var viewName = isJury ? "dbo.vw_JuryScoreboard" : "dbo.vw_PublicScoreboard";
    await using var conn = await Db.OpenAsync(connectionString);
    await using var cmd = new SqlCommand($"""
        SELECT rank_no, team_id, team_code, team_name, scoring_mode,
               solved_count, total_score, total_penalty, last_solved_at
        FROM {viewName}
        WHERE contest_id = @contestId
          AND (@mode IS NULL OR scoring_mode = @mode)
        ORDER BY rank_no, team_name;
        """, conn);
    cmd.Parameters.Add("@contestId", SqlDbType.Int).Value = contestId;
    cmd.Parameters.Add("@mode", SqlDbType.VarChar, 10).Value = (object?)mode ?? DBNull.Value;
    var rows = new List<object>();
    await using (var reader = await cmd.ExecuteReaderAsync())
    {
        while (await reader.ReadAsync())
        {
            rows.Add(new
            {
                rank = reader.GetInt64(0),
                teamId = reader.GetInt32(1),
                teamCode = reader.GetString(2),
                teamName = reader.GetString(3),
                scoringMode = reader.GetString(4),
                solved = reader.GetInt32(5),
                score = reader.GetDecimal(6),
                penalty = reader.GetInt32(7),
                lastSolvedAt = Db.NullableDate(reader, 8)
            });
        }
    }

    await using var cellCmd = new SqlCommand("""
        SELECT t.team_id, cp.problem_id, cp.problem_label,
               COUNT(v.submission_id) AS attempts,
               MAX(CASE WHEN v.result_code = 'AC' THEN 1 ELSE 0 END) AS solved,
               MAX(v.score) AS best_score,
               MAX(v.submitted_at) AS last_submitted_at,
               MAX(v.result_code) AS latest_result
        FROM dbo.Team t
        JOIN dbo.ContestProblem cp ON cp.contest_id = t.contest_id
        JOIN dbo.Contest c ON c.contest_id = t.contest_id
        LEFT JOIN dbo.vw_CurrentJudgement v
          ON v.contest_id = t.contest_id AND v.team_id = t.team_id AND v.problem_id = cp.problem_id
         AND (@isJury = 1 OR c.contest_status <> 'FROZEN' OR c.freeze_at IS NULL
              OR v.submitted_at <= c.freeze_at)
        WHERE t.contest_id = @contestId
        GROUP BY t.team_id, cp.problem_id, cp.problem_label
        ORDER BY t.team_id, cp.problem_label;
        """, conn);
    cellCmd.Parameters.Add("@contestId", SqlDbType.Int).Value = contestId;
    cellCmd.Parameters.Add("@isJury", SqlDbType.Bit).Value = isJury;
    var cells = new List<object>();
    await using (var reader = await cellCmd.ExecuteReaderAsync())
    {
        while (await reader.ReadAsync())
        {
            cells.Add(new
            {
                teamId = reader.GetInt32(0),
                problemId = reader.GetInt32(1),
                label = reader.GetString(2),
                attempts = reader.GetInt32(3),
                solved = reader.GetInt32(4) == 1,
                bestScore = Db.NullableDecimal(reader, 5),
                lastSubmittedAt = Db.NullableDate(reader, 6),
                latestResult = Db.NullableString(reader, 7)
            });
        }
    }
    return Results.Ok(new { visibility = isJury ? "jury" : "public", rows, cells });
});

app.MapGet("/api/submissions", async (int? contestId, int? teamId, string? teamCode, string? problemCode, string? result,
    int? take, int? skip) =>
{
    var pageSize = Math.Clamp(take ?? 50, 1, 200);
    var offset = Math.Max(skip ?? 0, 0);
    await using var conn = await Db.OpenAsync(connectionString);
    await using var cmd = new SqlCommand("""
        SELECT submission_id, contest_code, team_code, team_name, problem_code, problem_title,
               language_code, language_name, sequence_no, submitted_at, submission_status,
               result_code, score, runtime_ms, memory_kb, is_effective, judged_at,
               batch_code, judge_message
        FROM dbo.vw_SubmissionHistory
        WHERE (@contestId IS NULL OR EXISTS
              (SELECT 1 FROM dbo.Contest c WHERE c.contest_code = vw_SubmissionHistory.contest_code AND c.contest_id = @contestId))
          AND (@teamId IS NULL OR EXISTS
              (SELECT 1 FROM dbo.Team t WHERE t.team_code = vw_SubmissionHistory.team_code AND t.team_id = @teamId))
          AND (@teamCode IS NULL OR team_code = @teamCode)
          AND (@problemCode IS NULL OR problem_code = @problemCode)
          AND (@result IS NULL OR result_code = @result)
        ORDER BY submitted_at DESC, submission_id DESC
        OFFSET @skip ROWS FETCH NEXT @take ROWS ONLY;
        """, conn);
    cmd.Parameters.Add("@contestId", SqlDbType.Int).Value = (object?)contestId ?? DBNull.Value;
    cmd.Parameters.Add("@teamId", SqlDbType.Int).Value = (object?)teamId ?? DBNull.Value;
    cmd.Parameters.Add("@teamCode", SqlDbType.VarChar, 30).Value = (object?)teamCode ?? DBNull.Value;
    cmd.Parameters.Add("@problemCode", SqlDbType.VarChar, 20).Value = (object?)problemCode ?? DBNull.Value;
    cmd.Parameters.Add("@result", SqlDbType.VarChar, 10).Value = (object?)result ?? DBNull.Value;
    cmd.Parameters.Add("@skip", SqlDbType.Int).Value = offset;
    cmd.Parameters.Add("@take", SqlDbType.Int).Value = pageSize;
    var rows = new List<object>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(new
        {
            submissionId = reader.GetInt64(0),
            contestCode = reader.GetString(1),
            teamCode = reader.GetString(2),
            teamName = reader.GetString(3),
            problemCode = reader.GetString(4),
            problemTitle = reader.GetString(5),
            languageCode = reader.GetString(6),
            languageName = reader.GetString(7),
            sequence = reader.GetInt32(8),
            submittedAt = reader.GetDateTime(9),
            submissionStatus = reader.GetString(10),
            result = Db.NullableString(reader, 11),
            score = Db.NullableDecimal(reader, 12) ?? 0,
            runtimeMs = Db.NullableInt(reader, 13),
            memoryKb = Db.NullableInt(reader, 14),
            effective = Db.NullableBool(reader, 15),
            judgedAt = Db.NullableDate(reader, 16),
            rejudgeBatch = Db.NullableString(reader, 17),
            judgeMessage = Db.NullableString(reader, 18)
        });
    }
    return Results.Ok(rows);
});

app.MapGet("/api/submissions/{submissionId:long}/history", async (long submissionId) =>
{
    await using var conn = await Db.OpenAsync(connectionString);
    await using var cmd = new SqlCommand("""
        SELECT submission_id, contest_code, team_code, team_name, problem_code, problem_title,
               language_code, language_name, sequence_no, submitted_at, submission_status,
               judgement_id, result_code, score, runtime_ms, memory_kb, is_effective,
               judged_at, batch_code, judge_message
        FROM dbo.vw_SubmissionHistory
        WHERE submission_id = @submissionId
        ORDER BY judged_at DESC, judgement_id DESC;
        """, conn);
    cmd.Parameters.Add("@submissionId", SqlDbType.BigInt).Value = submissionId;
    var rows = new List<object>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(new
        {
            submissionId = reader.GetInt64(0),
            contestCode = reader.GetString(1),
            teamCode = reader.GetString(2),
            teamName = reader.GetString(3),
            problemCode = reader.GetString(4),
            problemTitle = reader.GetString(5),
            languageCode = reader.GetString(6),
            languageName = reader.GetString(7),
            sequence = reader.GetInt32(8),
            submittedAt = reader.GetDateTime(9),
            submissionStatus = reader.GetString(10),
            judgementId = Db.NullableLong(reader, 11),
            result = Db.NullableString(reader, 12),
            score = reader.GetDecimal(13),
            runtimeMs = Db.NullableInt(reader, 14),
            memoryKb = Db.NullableInt(reader, 15),
            effective = Db.NullableBool(reader, 16),
            judgedAt = Db.NullableDate(reader, 17),
            rejudgeBatch = Db.NullableString(reader, 18),
            judgeMessage = Db.NullableString(reader, 19)
        });
    }
    return rows.Count == 0 ? Results.NotFound(new { error = "提交记录不存在" }) : Results.Ok(rows);
});

app.MapGet("/api/problem-stats", async (int? contestId) =>
{
    await using var conn = await Db.OpenAsync(connectionString);
    await using var cmd = new SqlCommand("""
        SELECT contest_code, problem_code, title, submission_count,
               accepted_submission_count, accepted_rate, average_score, first_accepted_at
        FROM dbo.vw_ProblemStatistics s
        WHERE (@contestId IS NULL OR EXISTS
              (SELECT 1 FROM dbo.Contest c WHERE c.contest_code = s.contest_code AND c.contest_id = @contestId))
        ORDER BY contest_code, problem_code;
        """, conn);
    cmd.Parameters.Add("@contestId", SqlDbType.Int).Value = (object?)contestId ?? DBNull.Value;
    var rows = new List<object>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(new
        {
            contestCode = reader.GetString(0),
            problemCode = reader.GetString(1),
            title = reader.GetString(2),
            submissions = reader.GetInt32(3),
            accepted = reader.GetInt32(4),
            acceptedRate = Db.NullableDecimal(reader, 5) ?? 0,
            averageScore = Db.NullableDecimal(reader, 6) ?? 0,
            firstAcceptedAt = Db.NullableDate(reader, 7)
        });
    }
    return Results.Ok(rows);
});

app.MapGet("/api/team-performance", async (int? contestId) =>
{
    await using var conn = await Db.OpenAsync(connectionString);
    await using var cmd = new SqlCommand("""
        SELECT contest_code, team_code, team_name, submission_count, accepted_count,
               accepted_rate, average_runtime_ms, solved_problem_count
        FROM dbo.vw_TeamPerformance p
        WHERE (@contestId IS NULL OR EXISTS
              (SELECT 1 FROM dbo.Contest c WHERE c.contest_code = p.contest_code AND c.contest_id = @contestId))
        ORDER BY solved_problem_count DESC, accepted_rate DESC, team_name;
        """, conn);
    cmd.Parameters.Add("@contestId", SqlDbType.Int).Value = (object?)contestId ?? DBNull.Value;
    var rows = new List<object>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(new
        {
            contestCode = reader.GetString(0),
            teamCode = reader.GetString(1),
            teamName = reader.GetString(2),
            submissions = reader.GetInt32(3),
            accepted = reader.GetInt32(4),
            acceptedRate = Db.NullableDecimal(reader, 5) ?? 0,
            averageRuntimeMs = Db.NullableDecimal(reader, 6) ?? 0,
            solvedProblems = reader.GetInt32(7)
        });
    }
    return Results.Ok(rows);
});

app.MapGet("/api/analytics/{contestId:int}", async (int contestId) =>
{
    await using var conn = await Db.OpenAsync(connectionString);
    await using var languageCmd = new SqlCommand("""
        SELECT l.language_code, l.display_name,
               COUNT(s.submission_id) AS submission_count,
               SUM(CASE WHEN v.result_code = 'AC' THEN 1 ELSE 0 END) AS accepted_count
        FROM dbo.Submission s
        JOIN dbo.ProgrammingLanguage l ON l.language_id = s.language_id
        LEFT JOIN dbo.vw_CurrentJudgement v ON v.submission_id = s.submission_id
        WHERE s.contest_id = @contestId
        GROUP BY l.language_code, l.display_name
        ORDER BY submission_count DESC, l.language_code;
        """, conn);
    languageCmd.Parameters.Add("@contestId", SqlDbType.Int).Value = contestId;
    var languages = new List<object>();
    await using (var reader = await languageCmd.ExecuteReaderAsync())
    {
        while (await reader.ReadAsync())
        {
            languages.Add(new
            {
                code = reader.GetString(0),
                name = reader.GetString(1),
                submissions = reader.GetInt32(2),
                accepted = reader.GetInt32(3)
            });
        }
    }

    await using var resultCmd = new SqlCommand("""
        SELECT COALESCE(v.result_code, 'PENDING') AS result_code, COUNT(*) AS result_count
        FROM dbo.Submission s
        LEFT JOIN dbo.vw_CurrentJudgement v ON v.submission_id = s.submission_id
        WHERE s.contest_id = @contestId
        GROUP BY COALESCE(v.result_code, 'PENDING')
        ORDER BY result_count DESC, result_code;
        """, conn);
    resultCmd.Parameters.Add("@contestId", SqlDbType.Int).Value = contestId;
    var results = new List<object>();
    await using (var reader = await resultCmd.ExecuteReaderAsync())
    {
        while (await reader.ReadAsync())
        {
            results.Add(new { result = reader.GetString(0), count = reader.GetInt32(1) });
        }
    }
    return Results.Ok(new { languages, results });
});

app.MapGet("/api/rejudge/history", async (int? contestId) =>
{
    await using var conn = await Db.OpenAsync(connectionString);
    await using var cmd = new SqlCommand("""
        SELECT rb.batch_id, rb.contest_id, rb.batch_code, rb.reason, rb.batch_status,
               rb.created_at, rb.applied_at, u.display_name,
               COUNT(j.judgement_id) AS judgement_count
        FROM dbo.RejudgeBatch rb
        JOIN dbo.UserAccount u ON u.user_id = rb.created_by
        LEFT JOIN dbo.Judgement j ON j.rejudge_batch_id = rb.batch_id
        WHERE (@contestId IS NULL OR rb.contest_id = @contestId)
        GROUP BY rb.batch_id, rb.contest_id, rb.batch_code, rb.reason, rb.batch_status,
                 rb.created_at, rb.applied_at, u.display_name
        ORDER BY rb.created_at DESC;
        """, conn);
    cmd.Parameters.Add("@contestId", SqlDbType.Int).Value = (object?)contestId ?? DBNull.Value;
    var rows = new List<object>();
    await using var reader = await cmd.ExecuteReaderAsync();
    while (await reader.ReadAsync())
    {
        rows.Add(new
        {
            batchId = reader.GetInt64(0),
            contestId = reader.GetInt32(1),
            batchCode = reader.GetString(2),
            reason = reader.GetString(3),
            status = reader.GetString(4),
            createdAt = reader.GetDateTime(5),
            appliedAt = Db.NullableDate(reader, 6),
            createdBy = reader.GetString(7),
            judgementCount = reader.GetInt32(8)
        });
    }
    return Results.Ok(rows);
});

app.MapPost("/api/rejudge", async (RejudgeRequest request) =>
{
    if (request.ContestId <= 0 || string.IsNullOrWhiteSpace(request.Reason))
        return Results.BadRequest(new { error = "竞赛和重判原因不能为空" });

    try
    {
        await using var conn = await Db.OpenAsync(connectionString);
        await using var cmd = new SqlCommand("dbo.usp_ApplyRejudgeBatch", conn)
        {
            CommandType = CommandType.StoredProcedure
        };
        cmd.Parameters.Add("@ContestId", SqlDbType.Int).Value = request.ContestId;
        cmd.Parameters.Add("@ProblemId", SqlDbType.Int).Value = (object?)request.ProblemId ?? DBNull.Value;
        cmd.Parameters.Add("@TeamId", SqlDbType.Int).Value = (object?)request.TeamId ?? DBNull.Value;
        cmd.Parameters.Add("@Reason", SqlDbType.NVarChar, 500).Value = request.Reason.Trim();
        cmd.Parameters.Add("@CreatedBy", SqlDbType.Int).Value = request.CreatedBy;
        cmd.Parameters.Add("@ForceFailure", SqlDbType.Bit).Value = request.ForceFailure;
        var output = cmd.Parameters.Add("@BatchId", SqlDbType.BigInt);
        output.Direction = ParameterDirection.Output;
        await cmd.ExecuteNonQueryAsync();
        return Results.Ok(new { batchId = output.Value, message = "重判事务已提交" });
    }
    catch (SqlException ex)
    {
        return Results.BadRequest(new { error = ex.Message, type = "SQL_VALIDATION_ERROR" });
    }
});

app.Run();

record RejudgeRequest(int ContestId, int? ProblemId, int? TeamId, string Reason, int CreatedBy = 14, bool ForceFailure = false);

static class Db
{
    public static async Task<SqlConnection> OpenAsync(string connectionString)
    {
        var conn = new SqlConnection(connectionString);
        await conn.OpenAsync();
        return conn;
    }

    public static string? NullableString(IDataRecord reader, int ordinal) => reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
    public static DateTime? NullableDate(IDataRecord reader, int ordinal) => reader.IsDBNull(ordinal) ? null : reader.GetDateTime(ordinal);
    public static int? NullableInt(IDataRecord reader, int ordinal) => reader.IsDBNull(ordinal) ? null : reader.GetInt32(ordinal);
    public static long? NullableLong(IDataRecord reader, int ordinal) => reader.IsDBNull(ordinal) ? null : reader.GetInt64(ordinal);
    public static decimal? NullableDecimal(IDataRecord reader, int ordinal) => reader.IsDBNull(ordinal) ? null : reader.GetDecimal(ordinal);
    public static bool? NullableBool(IDataRecord reader, int ordinal) => reader.IsDBNull(ordinal) ? null : reader.GetBoolean(ordinal);
}
