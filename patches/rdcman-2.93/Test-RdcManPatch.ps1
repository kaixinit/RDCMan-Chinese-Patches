#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scripts\Common.ps1')
Assert-WindowsPatchHost
Assert-SourceBundle $PSScriptRoot
$config=Read-PatchJson (Join-Path $PSScriptRoot 'patch.json')
$directory=(Resolve-Path -LiteralPath $OutputDirectory -ErrorAction Stop).Path
$report=Read-PatchJson (Join-Path $directory 'patch-report.json')
$backup=Join-Path $directory 'backup\RDCMan.original.exe'
$target=Join-Path $directory 'RDCMan.exe'
if($report.SchemaVersion -ne 1 -or $report.OriginalSHA256 -cne $config.sourceSHA256 -or (Get-FileHash -LiteralPath $backup).Hash -cne $config.sourceSHA256){throw '输出报告或原版备份无效。'}
$targetHash=(Get-FileHash -LiteralPath $target).Hash
if($report.State -eq 'Original'){
    if($targetHash -cne $config.sourceSHA256){throw '已恢复的文件校验失败。'}
    return [pscustomobject]@{Passed=$true;State='Original';BackupAndRestoredFileMatch=$true}
}
if($report.State -cne 'Localized' -or $targetHash -cne $report.LocalizedSHA256){throw '汉化副本已改变或报告状态无效。'}
if($report.PatchDataSHA256 -cne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'patches\translations.json')).Hash){throw '当前翻译数据与构建报告不一致。'}
& (Join-Path $PSScriptRoot 'scripts\Verify-Pe.ps1') -SourcePath $backup -TargetPath $target -ReportPath (Join-Path $directory 'pe-recheck.json') | Out-Null
$runtime=Invoke-PatchRuntimeChecks $PSScriptRoot $target (Join-Path $directory 'runtime-recheck.json') $directory
[pscustomobject]@{Passed=$true;State='Localized';RuntimeCases=$runtime.Cases;NativeResourcesVerified=$true;SHA256=$targetHash}
