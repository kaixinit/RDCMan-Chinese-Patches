#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scripts\Common.ps1')
Assert-WindowsPatchHost
Assert-SourceBundle $PSScriptRoot
$config=Read-PatchJson (Join-Path $PSScriptRoot 'patch.json')
$directory=(Resolve-Path -LiteralPath $OutputDirectory -ErrorAction Stop).Path
$reportPath=Join-Path $directory 'patch-report.json'
$report=Read-PatchJson $reportPath
$target=Join-Path $directory 'RDCMan.exe'
$backup=Join-Path $directory 'backup\RDCMan.original.exe'
if($report.SchemaVersion -ne 1 -or $report.OriginalSHA256 -cne $config.sourceSHA256 -or $report.BackupFile -cne 'backup/RDCMan.original.exe'){throw '此目录不是受支持的补丁输出。'}
if((Get-FileHash -LiteralPath $backup).Hash -cne $config.sourceSHA256){throw '原版备份校验失败，未执行恢复。'}
$targetHash=(Get-FileHash -LiteralPath $target).Hash
if($report.State -eq 'Original'){
    if($targetHash -cne $config.sourceSHA256){throw '恢复状态与文件不一致，拒绝覆盖。'}
    return [pscustomobject]@{AlreadyRestored=$true;OriginalSHA256=$targetHash}
}
if($report.State -cne 'Localized' -or $targetHash -cne $report.LocalizedSHA256){throw '目标文件已被其他方式修改，拒绝覆盖。'}
Assert-TargetNotRunning $target
if(-not $PSCmdlet.ShouldProcess($target,'将此独立副本恢复为备份的微软原版，并保留汉化文件')){return}
$token=[Guid]::NewGuid().ToString('N')
$temporary=Join-Path $directory ('.restore-'+$token+'.tmp')
$savedLocalized=Join-Path $directory ('RDCMan.localized-'+$token+'.bak')
try {
    Copy-Item -LiteralPath $backup -Destination $temporary
    if((Get-FileHash -LiteralPath $temporary).Hash -cne $config.sourceSHA256){throw '恢复临时文件校验失败。'}
    [IO.File]::Replace($temporary,$target,$savedLocalized)
    $report.State='Original'
    $report | Add-Member -NotePropertyName RestoredAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $report | Add-Member -NotePropertyName SavedLocalizedFile -NotePropertyValue ([IO.Path]::GetFileName($savedLocalized)) -Force
    Write-PatchJson $reportPath $report
    [pscustomobject]@{Restored=$true;Executable=$target;OriginalSHA256=(Get-FileHash -LiteralPath $target).Hash;SavedLocalizedFile=[IO.Path]::GetFileName($savedLocalized)}
} finally {if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
