#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$CecilPath,
    [string]$CecilPackagePath,
    [switch]$DownloadDependency
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scripts\Common.ps1')
Assert-WindowsPatchHost
Assert-SourceBundle $PSScriptRoot
$config=Read-PatchJson (Join-Path $PSScriptRoot 'patch.json')
$source=(Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
if(-not [IO.File]::Exists($source)){throw 'SourcePath 必须是原版程序文件。'}
if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $config.sourceSHA256){throw '原版 SHA256 不匹配。仅支持指定的 2.93.1431.0；其他版本、已汉化副本和重复打补丁均会拒绝。'}
$output=Get-FullPatchPath $OutputDirectory
$output=$output.TrimEnd([IO.Path]::DirectorySeparatorChar)
if([IO.File]::Exists($output) -or [IO.Directory]::Exists($output)){throw '输出目录已存在。请指定一个新的目录，脚本不会覆盖已有文件。'}
$parent=[IO.Path]::GetDirectoryName($output)
if(-not $parent -or [string]::Equals($output,$source,[StringComparison]::OrdinalIgnoreCase)){throw '输出路径无效。'}
$translations=Join-Path $PSScriptRoot 'patches\translations.json'
Assert-TranslationData $translations $config.fixedTextOccurrences
if(-not $PSCmdlet.ShouldProcess($output,'由校验通过的原版生成独立汉化副本、原版备份和检查报告')){
    return [pscustomobject]@{Preview=$true;SourceVerified=$true;Version=$config.targetVersion;OutputDirectory=$output;NetworkUsed=$false}
}
if($CecilPath -and ($CecilPackagePath -or $DownloadDependency)){throw 'CecilPath 不能与依赖包或下载选项同时指定。'}
if(-not $CecilPath){
    $dependencyArgs=@{}
    if($CecilPackagePath){$dependencyArgs.PackagePath=$CecilPackagePath}
    if($DownloadDependency){$dependencyArgs.Download=$true}
    $CecilPath=& (Join-Path $PSScriptRoot 'Prepare-Dependency.ps1') @dependencyArgs
}
$cecil=(Resolve-Path -LiteralPath $CecilPath -ErrorAction Stop).Path
$expectedDllHash=if($PSVersionTable.PSEdition -eq 'Desktop'){$config.dependency.net40SHA256}else{$config.dependency.netstandard20SHA256}
if((Get-FileHash -LiteralPath $cecil).Hash -cne $expectedDllHash){throw 'Mono.Cecil.dll 校验失败或目标框架不匹配，请运行 Prepare-Dependency.ps1。'}
foreach($loaded in [AppDomain]::CurrentDomain.GetAssemblies()){
    if($loaded.GetName().Name -eq 'Mono.Cecil'){
        if(-not $loaded.Location -or (Get-FileHash -LiteralPath $loaded.Location).Hash -cne $expectedDllHash){throw '此会话载入了不同的 Mono.Cecil，请在新的 PowerShell 窗口重试。'}
    }
}
[IO.Directory]::CreateDirectory($parent) | Out-Null
$staging=Join-Path $parent ('.rdcman-patch-'+[Guid]::NewGuid().ToString('N'))
if([IO.Directory]::Exists($staging)){throw '临时目录冲突。'}
[IO.Directory]::CreateDirectory($staging) | Out-Null
$succeeded=$false
try {
    Copy-Item -LiteralPath $source -Destination (Join-Path $staging 'RDCMan.original.exe')
    Copy-Item -LiteralPath $translations -Destination (Join-Path $staging 'patches.json')
    & (Join-Path $PSScriptRoot 'scripts\Apply-Strings.ps1') -WorkRoot $staging -CecilPath $cecil | Out-Null
    & (Join-Path $PSScriptRoot 'scripts\Apply-Ui.ps1') -WorkRoot $staging -CecilPath $cecil | Out-Null
    $localized=Join-Path $staging 'RDCMan.zh.exe'
    & (Join-Path $PSScriptRoot 'scripts\Verify-Pe.ps1') -SourcePath $source -TargetPath $localized -ReportPath (Join-Path $staging 'pe-verification.json') | Out-Null
    $runtime=Invoke-PatchRuntimeChecks $PSScriptRoot $localized (Join-Path $staging 'runtime-verification.json') $staging
    if((Get-FileHash -LiteralPath $source).Hash -cne $config.sourceSHA256){throw '构建期间原版文件发生变化，未交付结果。'}
    $product=Join-Path $staging 'product'
    [IO.Directory]::CreateDirectory((Join-Path $product 'backup')) | Out-Null
    Copy-Item -LiteralPath (Join-Path $staging 'RDCMan.original.exe') -Destination (Join-Path $product 'backup\RDCMan.original.exe')
    Copy-Item -LiteralPath $localized -Destination (Join-Path $product 'RDCMan.exe')
    $assembly=Read-PatchJson (Join-Path $staging 'assembly-verification.json')
    $report=[ordered]@{
        SchemaVersion=1;PackageVersion=$config.packageVersion;SoftwareVersion=$config.targetVersion;State='Localized'
        OriginalSHA256=$config.sourceSHA256;LocalizedSHA256=(Get-FileHash -LiteralPath $localized).Hash
        PatchDataSHA256=(Get-FileHash -LiteralPath $translations).Hash;BackupFile='backup/RDCMan.original.exe'
        OriginalSignatureStatus=[string](Get-AuthenticodeSignature -LiteralPath $source).Status
        ModifiedCopyUnsigned=$true;FixedTextOccurrences=$config.fixedTextOccurrences
        AssemblyVerification=$assembly;PeVerification=(Read-PatchJson (Join-Path $staging 'pe-verification.json'))
        RuntimeVerification=$runtime;DependencyVersion=$config.dependency.version
        CreatedAtUtc=[DateTime]::UtcNow.ToString('o');NoApplicationStarted=$true;NoSettingsModified=$true
    }
    Write-PatchJson (Join-Path $product 'patch-report.json') $report
    [IO.Directory]::Move($product,$output)
    $succeeded=$true
    [pscustomobject]@{Completed=$true;OutputDirectory=$output;Executable=(Join-Path $output 'RDCMan.exe');FixedTexts=$config.fixedTextOccurrences;RuntimeCases=$runtime.Cases;OriginalUnchanged=$true;SHA256=$report.LocalizedSHA256}
} catch {
    $reason=$_.Exception.Message
    $failure=[ordered]@{Completed=$false;Reason=$reason;ScriptStack=$_.ScriptStackTrace;Position=$_.InvocationInfo.PositionMessage;RecordedAtUtc=[DateTime]::UtcNow.ToString('o')}
    try {Write-PatchJson (Join-Path $staging 'failure-report.json') $failure} catch {Write-Verbose '无法写入失败报告。'}
    if($reason.Length -gt 1200){$reason=$reason.Substring(0,1200)+'…（详细材料见临时目录）'}
    throw ('生成失败，未覆盖原版或已有输出。检查材料保留在 '+$staging+'。原因：'+$reason)
} finally {
    if($succeeded){
        # Delete only this invocation's generated staging directory, never an input/output directory.
        $resolvedStage=[IO.Path]::GetFullPath($staging)
        if([IO.Path]::GetDirectoryName($resolvedStage) -cne [IO.Path]::GetFullPath($parent) -or [IO.Path]::GetFileName($resolvedStage) -notmatch '^\.rdcman-patch-[0-9a-f]{32}$'){throw '临时目录清理边界检查失败。'}
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
