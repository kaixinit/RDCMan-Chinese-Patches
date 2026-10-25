#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$CecilPath,[Parameter(Mandatory=$true)][string]$WorkDirectory,[string]$PythonPath)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts\Common.ps1')
$work=Get-FullPatchPath $WorkDirectory
if(Test-Path -LiteralPath $work){throw '测试工作目录必须是新的目录。'}
[IO.Directory]::CreateDirectory($work) | Out-Null
$source=(Resolve-Path -LiteralPath $SourcePath).Path
$initial=(Get-FileHash -LiteralPath $source).Hash
$cases=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Condition){if(-not $Condition){throw ('测试失败：'+$Name)};$cases.Add([pscustomobject]@{Name=$Name;Passed=$true})}
function Expect-Rejection([string]$Name,[scriptblock]$Action){
    $rejected=$false
    try {& $Action | Out-Null} catch {$rejected=$true}
    Check $Name $rejected
}
$invalid=Join-Path $work 'invalid.exe'
[IO.File]::WriteAllText($invalid,'not-an-rdcman-binary')
Expect-Rejection '错误输入被拒绝' {& (Join-Path $root 'Apply-RdcManPatch.ps1') -SourcePath $invalid -OutputDirectory (Join-Path $work 'invalid-output') -CecilPath $CecilPath}
Check '错误输入不创建输出目录' (-not (Test-Path -LiteralPath (Join-Path $work 'invalid-output')))
$existing=Join-Path $work 'existing'
[IO.Directory]::CreateDirectory($existing) | Out-Null
[IO.File]::WriteAllText((Join-Path $existing 'keep.txt'),'keep')
Expect-Rejection '已有输出目录被保护' {& (Join-Path $root 'Apply-RdcManPatch.ps1') -SourcePath $source -OutputDirectory $existing -CecilPath $CecilPath}
Check '已有目录内容保持不变' ([IO.File]::ReadAllText((Join-Path $existing 'keep.txt')) -ceq 'keep')
$preview=Join-Path $work 'preview'
& (Join-Path $root 'Apply-RdcManPatch.ps1') -SourcePath $source -OutputDirectory $preview -WhatIf | Out-Null
Check 'WhatIf 不写输出' (-not (Test-Path -LiteralPath $preview))
Expect-Rejection '错误依赖被拒绝' {& (Join-Path $root 'Apply-RdcManPatch.ps1') -SourcePath $source -OutputDirectory (Join-Path $work 'bad-dependency') -CecilPath $invalid}
$product=Join-Path $work 'generated'
$pythonArgs=@{};if($PythonPath){$pythonArgs.PythonPath=$PythonPath}
$result=& (Join-Path $root 'Apply-RdcManPatch.ps1') -SourcePath $source -OutputDirectory $product -CecilPath $CecilPath @pythonArgs
Check '完整构建及 261 项未修改捆绑文件校验通过' ($result.Completed -and $result.BundleFilesUnchanged -eq 261)
$readback=& (Join-Path $root 'Test-RdcManPatch.ps1') -OutputDirectory $product @pythonArgs
Check '结果可独立复检' $readback.Passed
Expect-Rejection '重复汉化输入被拒绝' {& (Join-Path $root 'Apply-RdcManPatch.ps1') -SourcePath (Join-Path $product 'RDCMan.exe') -OutputDirectory (Join-Path $work 'double-apply') -CecilPath $CecilPath}
$localizedHash=(Get-FileHash -LiteralPath (Join-Path $product 'RDCMan.exe')).Hash
& (Join-Path $root 'Restore-RdcManPatch.ps1') -OutputDirectory $product -WhatIf | Out-Null
Check '恢复预览不修改文件' ((Get-FileHash -LiteralPath (Join-Path $product 'RDCMan.exe')).Hash -ceq $localizedHash)
$tampered=Join-Path $work 'tampered'
Copy-Item -LiteralPath $product -Destination $tampered -Recurse
[IO.File]::AppendAllText((Join-Path $tampered 'RDCMan.exe'),'test-only-tampering')
$tamperedHash=(Get-FileHash -LiteralPath (Join-Path $tampered 'RDCMan.exe')).Hash
Expect-Rejection '恢复拒绝覆盖额外修改的副本' {& (Join-Path $root 'Restore-RdcManPatch.ps1') -OutputDirectory $tampered}
Check '被拒绝的目标保持不变' ((Get-FileHash -LiteralPath (Join-Path $tampered 'RDCMan.exe')).Hash -ceq $tamperedHash)
$restored=& (Join-Path $root 'Restore-RdcManPatch.ps1') -OutputDirectory $product
Check '恢复后字节与原版完全一致' ($restored.Restored -and (Get-FileHash -LiteralPath (Join-Path $product 'RDCMan.exe')).Hash -ceq $initial)
$restoredCheck=& (Join-Path $root 'Test-RdcManPatch.ps1') -OutputDirectory $product @pythonArgs
Check '恢复状态可以复检' ($restoredCheck.Passed -and $restoredCheck.State -eq 'Original')
$again=& (Join-Path $root 'Restore-RdcManPatch.ps1') -OutputDirectory $product
Check '重复恢复不会覆盖文件' $again.AlreadyRestored
Check '用户提供的原版从未改变' ((Get-FileHash -LiteralPath $source).Hash -ceq $initial)
$report=[ordered]@{Passed=$true;Cases=$cases.Count;PowerShell=$PSVersionTable.PSVersion.ToString();Results=@($cases)}
Write-PatchJson (Join-Path $work 'workflow-report.json') $report
[pscustomobject]@{Passed=$true;WorkflowCases=$cases.Count;BundleFilesUnchanged=261;Report=(Join-Path $work 'workflow-report.json')}
