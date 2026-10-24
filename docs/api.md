# API 说明

前端通过同源 `fetch` 请求以下接口，响应格式为 JSON。数据库访问使用 `Microsoft.Data.SqlClient`，筛选值作为 SQL 参数传入。赛事编号应从赛事列表读取。

| 方法 | 路径 | 参数与返回内容 |
| --- | --- | --- |
| GET | `/api/health` | Web 进程状态，不建立数据库连接 |
| GET | `/api/contests` | 赛事列表、计分模式、状态和记录数量 |
| GET | `/api/contests/{contestId}` | 赛事详情、赛题和参赛队伍 |
| GET | `/api/metrics/{contestId}` | 队伍数、题目数、提交数、通过数及封榜隐藏提交数 |
| GET | `/api/scoreboard/{contestId}` | `mode=ICPC` 或 `IOI`；`visibility=public` 或 `jury`。返回排名行 `rows` 和逐题单元格 `cells` |
| GET | `/api/submissions` | 可选 `contestId`、`teamId`、`teamCode`、`problemCode`、`result`、`take`、`skip`；`take` 限制为 1–200 |
| GET | `/api/submissions/{submissionId}/history` | 按评测时间及评测编号倒序返回该提交的所有版本 |
| GET | `/api/problem-stats` | 可选 `contestId`；题目提交数、通过率、平均分和首次通过时间 |
| GET | `/api/team-performance` | 可选 `contestId`；队伍提交数、通过率、平均耗时和解题数 |
| GET | `/api/analytics/{contestId}` | 语言使用情况和当前评测结果分布 |
| GET | `/api/rejudge/history` | 可选 `contestId`；重判批次及关联的评测条数 |
| POST | `/api/rejudge` | 执行重判事务 |

`/api/submissions` 查询评测历史视图，同一提交存在多个评测版本时会返回多行。前端通过 `effective` 区分当前结果和历史记录。

## 榜单

```http
GET /api/scoreboard/1?mode=ICPC&visibility=public
```

后端按 `visibility` 选择公开榜或裁判榜视图。公开榜的逐题查询使用相同的封榜时间条件。`mode` 为其他非空值时，接口返回 HTTP 400。

## 重判

```json
{
  "contestId": 1,
  "problemId": 1,
  "teamId": 1,
  "reason": "核对评测版本",
  "createdBy": 14,
  "forceFailure": false
}
```

`contestId` 和非空 `reason` 必填。`problemId`、`teamId` 为 `null` 时不限制相应范围。`createdBy` 对应数据库中的用户主键，样例库的裁判编号为 14。

接口调用 `dbo.usp_ApplyRejudgeBatch`，成功返回批次编号 `batchId`。`forceFailure=true` 会在事务中触发测试异常，用于核对旧有效结果和批次记录是否恢复；SQL 校验异常返回 HTTP 400 与 `SQL_VALIDATION_ERROR`。

当前批次过程依据已有有效评测生成新版本，保留其结果和分数。对接实际判题服务时，需要将判题输出写入版本流程。

## 页面与数据库对象

| 页面 | 数据来源 |
| --- | --- |
| 赛事总览 | `Contest`、`Team`、`ContestProblem`、`Submission` 及当前评测查询 |
| 实时榜单 | `vw_PublicScoreboard`、`vw_JuryScoreboard` 和逐题聚合 |
| 提交记录 | `vw_SubmissionHistory` |
| 数据分析 | `vw_ProblemStatistics`、`vw_TeamPerformance` 及语言、结果分布查询 |
| 重判管理 | `usp_ApplyRejudgeBatch`、`RejudgeBatch` 与 `Judgement` |
