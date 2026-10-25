#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$CecilPath,
    [string]$CecilPackagePath,
    [switch]$DownloadDependency,
    [string]$PythonPath,
    [string]$VCRuntimePackagePath,
    [string]$VCRuntimePath
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scripts\Common.ps1')
Assert-WindowsPatchHost
Assert-SourceBundle $PSScriptRoot
$config=Read-PatchJson (Join-Path $PSScriptRoot 'patch.json')
$source=(Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
if(-not [IO.File]::Exists($source) -or (Get-FileHash -LiteralPath $source).Hash -cne $config.sourceSHA256){throw '原版 SHA256 不匹配。仅支持指定的 3.22 x86 原版，其他版本、x64、已有汉化副本均会拒绝。'}
$output=(Get-FullPatchPath $OutputDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar)
if(Test-Path -LiteralPath $output){throw '输出目录已存在，请指定新的目录；脚本不会覆盖已有文件。'}
$parent=[IO.Path]::GetDirectoryName($output)
if(-not $parent -or [string]::Equals($output,$source,[StringComparison]::OrdinalIgnoreCase)){throw '输出路径无效。'}
$translations=Join-Path $PSScriptRoot 'patches\translations.json'
Assert-TranslationData $translations $config.fixedTextOccurrences
if(-not $PSCmdlet.ShouldProcess($output,'由校验通过的 3.22 x86 原版生成汉化副本、原版备份和检查报告')){return [pscustomobject]@{Preview=$true;SourceVerified=$true;Version=$config.targetVersion;OutputDirectory=$output;NetworkUsed=$false}}
$python=Get-PatchPython $PythonPath
if($CecilPath -and ($CecilPackagePath -or $DownloadDependency)){throw 'CecilPath 不能与依赖包或下载选项同时指定。'}
if(-not $CecilPath){
    $dependencyArgs=@{}
    if($CecilPackagePath){$dependencyArgs.PackagePath=$CecilPackagePath}
    if($DownloadDependency){$dependencyArgs.Download=$true}
    $CecilPath=& (Join-Path $PSScriptRoot 'Prepare-Dependency.ps1') @dependencyArgs
}
$cecil=(Resolve-Path -LiteralPath $CecilPath -ErrorAction Stop).Path
$expectedDllHash=if($PSVersionTable.PSEdition -eq 'Desktop'){$config.dependency.net40SHA256}else{$config.dependency.netstandard20SHA256}
if((Get-FileHash -LiteralPath $cecil).Hash -cne $expectedDllHash){throw 'Mono.Cecil.dll 校验失败或目标框架不匹配。'}
foreach($loaded in [AppDomain]::CurrentDomain.GetAssemblies()){
    if($loaded.GetName().Name -eq 'Mono.Cecil' -and (-not $loaded.Location -or (Get-FileHash -LiteralPath $loaded.Location).Hash -cne $expectedDllHash)){throw '当前会话已载入不同的 Mono.Cecil，请打开新的 PowerShell 窗口。'}
}
if($VCRuntimePath -and $VCRuntimePackagePath){throw 'VCRuntimePath 与 VCRuntimePackagePath 不能同时指定。'}
if(-not $VCRuntimePath){
    $runtimeArgs=@{}
    if($PythonPath){$runtimeArgs.PythonPath=$PythonPath}
    if($VCRuntimePackagePath){$runtimeArgs.PackagePath=$VCRuntimePackagePath}
    elseif($DownloadDependency){$runtimeArgs.Download=$true}
    $VCRuntimePath=& (Join-Path $PSScriptRoot 'Prepare-Runtime.ps1') @runtimeArgs
}
$runtime=(Resolve-Path -LiteralPath $VCRuntimePath -ErrorAction Stop).Path
Assert-NativeRuntime $runtime $config
[void][IO.Directory]::CreateDirectory($parent)
$staging=Join-Path $parent ('.rdcman-patch-'+[Guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $staging){throw '临时目录冲突。'}
[void][IO.Directory]::CreateDirectory($staging)
$succeeded=$false
try {
    $original=Join-Path $staging 'RDCMan.original.exe'
    $originalDll=Join-Path $staging 'RDCMan.original.dll'
    Copy-Item -LiteralPath $source -Destination $original
    Copy-Item -LiteralPath $translations -Destination (Join-Path $staging 'patches.json')
    $extractReport=Join-Path $staging 'extract-report.json'
    Invoke-BundleTool $python @('extract','--source',$original,'--assembly',$originalDll,'--references',(Join-Path $staging 'references'),'--report',$extractReport)
    if((Get-FileHash -LiteralPath $originalDll).Hash -cne $config.sourceAssemblySHA256){throw '包内应用程序集校验失败。'}
    & (Join-Path $PSScriptRoot 'scripts\Apply-Strings.ps1') -WorkRoot $staging -CecilPath $cecil | Out-Null
    & (Join-Path $PSScriptRoot 'scripts\Apply-Ui.ps1') -WorkRoot $staging -CecilPath $cecil | Out-Null
    $localized=Join-Path $staging 'RDCMan.localized.exe'
    $bundleReport=Join-Path $staging 'bundle-verification.json'
    Invoke-BundleTool $python @('repack','--source',$original,'--assembly',(Join-Path $staging 'RDCMan.zh.dll'),'--runtime-directory',$runtime,'--target',$localized,'--report',$bundleReport)
    $assembly=Read-PatchJson (Join-Path $staging 'assembly-verification.json')
    $bundle=Read-PatchJson $bundleReport
    if(-not $bundle.Passed -or $bundle.UnchangedBundledFiles -ne $config.unchangedBundledFiles -or $bundle.AddedNativeRuntimeFiles.Count -ne $config.nativeRuntime.files.Count -or $bundle.LocalizedAssemblySHA256 -cne $assembly.LocalizedAssemblySHA256){throw '程序集或单文件包复核失败。'}
    if((Get-FileHash -LiteralPath $source).Hash -cne $config.sourceSHA256){throw '构建期间原版发生变化，未交付结果。'}
    $product=Join-Path $staging 'product'
    [void][IO.Directory]::CreateDirectory((Join-Path $product 'backup'))
    Copy-Item -LiteralPath $original -Destination (Join-Path $product 'backup\RDCMan.original.exe')
    Copy-Item -LiteralPath $localized -Destination (Join-Path $product 'RDCMan-x86.exe')
    $launcher="@echo off`r`nstart `"`" `"%~dp0RDCMan-x86.exe`"`r`n"
    [IO.File]::WriteAllText((Join-Path $product '启动中文版.cmd'),$launcher,[Text.Encoding]::ASCII)
    $compatibility="@echo off`r`nstart `"`" `"%~dp0RDCMan-x86.exe`" -mstsc /noopen /noconnect`r`n"
    [IO.File]::WriteAllText((Join-Path $product '启动兼容模式.cmd'),$compatibility,[Text.Encoding]::ASCII)
    $report=[ordered]@{
        SchemaVersion=1;PackageVersion=$config.packageVersion;SoftwareVersion=$config.targetVersion;State='Localized'
        OriginalSHA256=$config.sourceSHA256;LocalizedSHA256=(Get-FileHash -LiteralPath $localized).Hash
        PatchDataSHA256=(Get-FileHash -LiteralPath $translations).Hash;BackupFile='backup/RDCMan.original.exe'
        OriginalSignatureStatus=[string](Get-AuthenticodeSignature -LiteralPath $source).Status
        ModifiedCopyUnsigned=$true;FixedTextOccurrences=$config.fixedTextOccurrences
        AssemblyVerification=$assembly;BundleVerification=$bundle;PythonVersion=$python.Version
        DependencyVersion=$config.dependency.version;CreatedAtUtc=[DateTime]::UtcNow.ToString('o')
        NoApplicationStarted=$true;NoSettingsModified=$true;DefaultEngine='RDCore';DefaultStartupArguments='';NativeRuntimeVersion=$config.nativeRuntime.version
        CompatibilityLauncher='启动兼容模式.cmd';CompatibilityArguments='-mstsc /noopen /noconnect'
    }
    Write-PatchJson (Join-Path $product 'patch-report.json') $report
    if(Test-Path -LiteralPath $output){throw '输出目录在构建期间被创建，未覆盖。'}
    [IO.Directory]::Move($product,$output)
    $succeeded=$true
    [pscustomobject]@{Completed=$true;OutputDirectory=$output;Executable=(Join-Path $output 'RDCMan-x86.exe');FixedTexts=$config.fixedTextOccurrences;BundleFilesUnchanged=$bundle.UnchangedBundledFiles;NativeRuntimeFiles=$bundle.AddedNativeRuntimeFiles.Count;DefaultEngine='RDCore';OriginalUnchanged=$true;SHA256=$report.LocalizedSHA256}
} catch {
    $reason=$_.Exception.Message
    try {Write-PatchJson (Join-Path $staging 'failure-report.json') ([ordered]@{Completed=$false;Reason=$reason;ScriptStack=$_.ScriptStackTrace;Position=$_.InvocationInfo.PositionMessage})} catch {Write-Verbose '无法写入失败报告。'}
    if($reason.Length -gt 1200){$reason=$reason.Substring(0,1200)+'…'}
    throw ('生成失败，检查材料保留在 '+$staging+'。原因：'+$reason)
} finally {
    if($succeeded){
        $resolvedStage=[IO.Path]::GetFullPath($staging)
        if([IO.Path]::GetDirectoryName($resolvedStage) -cne [IO.Path]::GetFullPath($parent) -or [IO.Path]::GetFileName($resolvedStage) -notmatch '^\.rdcman-patch-[0-9a-f]{32}$'){throw '临时目录清理边界检查失败。'}
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
