param(
    [string]$ServerInstance = 'localhost',
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,127}$')]
    [string]$DatabaseName = 'AlgorithmContestDB'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$databaseRoot = Join-Path $repositoryRoot 'database'

function New-ConnectionString([string]$Database) {
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder['Data Source'] = $ServerInstance
    $builder['Initial Catalog'] = $Database
    $builder['Integrated Security'] = $true
    $builder['TrustServerCertificate'] = $true
    $builder['Encrypt'] = $false
    $builder['Connect Timeout'] = 15
    return $builder.ConnectionString
}

function Invoke-SqlBatches([string]$Sql, [string]$Database) {
    $connection = New-Object System.Data.SqlClient.SqlConnection (New-ConnectionString $Database)
    try {
        $connection.Open()
        foreach ($batch in [regex]::Split($Sql, '(?im)^\s*GO\s*(?:--.*)?$')) {
            if ([string]::IsNullOrWhiteSpace($batch)) { continue }
            $command = $connection.CreateCommand()
            try {
                $command.CommandTimeout = 300
                $command.CommandText = $batch
                [void]$command.ExecuteNonQuery()
            }
            finally { $command.Dispose() }
        }
    }
    finally { $connection.Dispose() }
}

$connection = New-Object System.Data.SqlClient.SqlConnection (New-ConnectionString 'master')
try {
    $connection.Open()
    $command = $connection.CreateCommand()
    try {
        $command.CommandText = 'SELECT DB_ID(@name)'
        [void]$command.Parameters.Add('@name', [System.Data.SqlDbType]::NVarChar, 128)
        $command.Parameters['@name'].Value = $DatabaseName
        $databaseId = $command.ExecuteScalar()
    }
    finally { $command.Dispose() }
}
finally { $connection.Dispose() }

if ($null -ne $databaseId -and $databaseId -isnot [System.DBNull]) {
    Write-Host "数据库 $DatabaseName 已存在，保留现有数据。"
    return
}

Write-Host "创建数据库 $DatabaseName"
Invoke-SqlBatches "CREATE DATABASE [$DatabaseName]" 'master'
foreach ($name in @('01_schema.sql', '03_objects.sql', '02_seed.sql')) {
    Write-Host "执行 $name"
    $sql = Get-Content -LiteralPath (Join-Path $databaseRoot $name) -Raw -Encoding UTF8
    if ($DatabaseName -ne 'AlgorithmContestDB') {
        $sql = $sql.Replace('AlgorithmContestDB', $DatabaseName)
    }
    Invoke-SqlBatches $sql $DatabaseName
}
Write-Host '数据库初始化完成。'
