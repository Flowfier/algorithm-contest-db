USE master;
GO
SET NOCOUNT ON;
DECLARE @BackupDir NVARCHAR(4000) = CONVERT(NVARCHAR(4000), SERVERPROPERTY('InstanceDefaultBackupPath'));
IF NULLIF(@BackupDir, N'') IS NULL
    THROW 54000, N'无法读取实例备份目录，请在脚本中指定 SQL Server 服务账户可写的目录。', 1;

DECLARE @Separator NCHAR(1) = CASE WHEN CHARINDEX(N'/', @BackupDir) > 0 THEN N'/' ELSE N'\' END;
IF RIGHT(@BackupDir, 1) NOT IN (N'\', N'/') SET @BackupDir += @Separator;
DECLARE @Stamp VARCHAR(40) = CONVERT(CHAR(8), GETDATE(), 112) + '_' +
    REPLACE(CONVERT(CHAR(8), GETDATE(), 108), ':', '') + '_' +
    LEFT(CONVERT(VARCHAR(36), NEWID()), 8);
DECLARE @BackupFile NVARCHAR(4000) = @BackupDir + N'AlgorithmContestDB_' + @Stamp + N'.bak';

-- 运行前请确保数据库服务账户对该目录具有写权限。
DECLARE @BackupSql NVARCHAR(MAX) =
    N'BACKUP DATABASE [AlgorithmContestDB] TO DISK = N''' +
    REPLACE(@BackupFile,'''','''''') +
    N''' WITH INIT, CHECKSUM, STATS = 10;';
EXEC sys.sp_executesql @BackupSql;

DECLARE @VerifySql NVARCHAR(MAX) =
    N'RESTORE VERIFYONLY FROM DISK = N''' +
    REPLACE(@BackupFile,'''','''''') + N''';';
EXEC sys.sp_executesql @VerifySql;

PRINT N'备份完成并通过 RESTORE VERIFYONLY 校验：' + @BackupFile;
PRINT N'恢复示例（请在确认覆盖目标数据库后执行）：';
PRINT N'ALTER DATABASE [AlgorithmContestDB] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
PRINT N'RESTORE DATABASE [AlgorithmContestDB] FROM DISK = N''' + @BackupFile + N''' WITH REPLACE, RECOVERY;';
PRINT N'ALTER DATABASE [AlgorithmContestDB] SET MULTI_USER;';
GO
