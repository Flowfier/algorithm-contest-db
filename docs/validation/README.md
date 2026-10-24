# 验证记录

本目录保存原项目样例库的本地验收快照，对应报告中的测试数据与页面截图。记录中的提交编号、批次编号和时间由当时的数据库状态决定。使用当前源码重新运行时，应以本次执行结果为准。

| 文件 | 验证内容 |
| --- | --- |
| [04_tests.log](04_tests.log) | 14 项断言通过，0 项失败 |
| [05_performance.log](05_performance.log) | 同一查询下，Submission 逻辑读从 47 降至 5，Judgement 保持 9；两次均返回 315 次尝试及最高分 100 |
| [06_backup_restore.log](06_backup_restore.log) | 完整备份与 RESTORE VERIFYONLY 校验输出 |
| [build.log](build.log) | 本地 Debug 构建完成，0 个警告、0 个错误 |
| [web_api.log](web_api.log) | 接口调用的 HTTP 状态码与响应摘要，含非法模式返回 400 的记录 |
| [web_browser_acceptance.log](web_browser_acceptance.log) | 浏览器验收范围及 7 张截图列表 |
| [browser_check.json](browser_check.json) | 浏览器页面错误检查与截图数量 |
| [web_rejudge_failure.json](web_rejudge_failure.json) | 模拟重判失败的接口响应 |
| [web_rejudge_success.json](web_rejudge_success.json) | 成功重判返回的批次编号 |

`web_api.log` 中的响应按摘要长度截取，完整 JSON 请求与字段说明见 [API 说明](../api.md)。备份及构建日志中的本机项目目录以 `<project-root>` 表示。备份集通过校验后，实际恢复仍需另行执行并核对数据库状态。

功能、性能和备份脚本的运行方法见 [项目说明](../../README.md)。GitHub Actions 的构建与 JavaScript 语法检查记录可在仓库 Actions 页面查看。
