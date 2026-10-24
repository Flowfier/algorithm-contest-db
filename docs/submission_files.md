# 项目提交文件清单

| 路径 | 内容 |
| --- | --- |
| [database/00_reset.sql](../database/00_reset.sql) | 重置并创建数据库 |
| [database/01_schema.sql](../database/01_schema.sql) | 11 张核心表及约束 |
| [database/02_seed.sql](../database/02_seed.sql) | 竞赛、队伍、题目和评测样例数据 |
| [database/03_objects.sql](../database/03_objects.sql) | 视图、索引、存储过程和触发器 |
| [database/04_tests.sql](../database/04_tests.sql) | 功能、约束、重判和榜单测试 |
| [database/05_performance.sql](../database/05_performance.sql) | 性能数据及索引对比 |
| [database/06_backup_restore.sql](../database/06_backup_restore.sql) | 完整备份、备份集校验及恢复命令 |
| [web/](../web/) | ASP.NET Core 8 API 和静态页面源码 |
| [docs/er_diagram.png](er_diagram.png)、[docs/architecture.png](architecture.png) | E-R 图和系统架构图 |
| [docs/web_final_desktop.png](web_final_desktop.png)、[docs/web_final_mobile.png](web_final_mobile.png) | 桌面端和移动端页面截图 |
| [docs/report_expansion_assets/](report_expansion_assets/) | 总览、榜单、IOI、分析、历史和重判验收截图 |
| [docs/validation/](validation/) | SQL、性能、备份、Web API、浏览器及编译日志 |

运行入口为 [README](../README.md)，初始化脚本为 [scripts/init-database.ps1](../scripts/init-database.ps1)。接口说明见 [api.md](api.md)，数据库设计见 [database.md](database.md)。
