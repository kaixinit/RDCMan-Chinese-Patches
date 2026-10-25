#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scripts\Common.ps1')
# Explicit source allowlist. Never collect build outputs, binaries, local settings, or dependencies.
$files=@(
    '.gitignore','.gitattributes','README.md','NOTICE.md','CHANGELOG.md','patch.json',
    'Apply-RdcManPatch.ps1','Prepare-Dependency.ps1','Restore-RdcManPatch.ps1','Test-RdcManPatch.ps1',
    'Update-SourceManifest.ps1','Package-Source.ps1',
    'patches/translations.json','scripts/Common.ps1','scripts/Apply-Strings.ps1','scripts/Apply-Ui.ps1','scripts/Verify-Pe.ps1',
    'tests/RuntimeChecks.cs','tests/Test-Workflow.ps1','docs/中英对照.tsv','docs/维护说明.md','docs/依赖说明.md','docs/验证记录.md'
)
$rows=@(foreach($relative in $files){
    $path=Join-Path $PSScriptRoot $relative
    if(-not [IO.File]::Exists($path)){throw ('缺少应交付的源文件：'+$relative)}
    [pscustomobject]@{path=$relative;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $path).Length}
})
Write-PatchJson (Join-Path $PSScriptRoot 'source-manifest.json') ([ordered]@{schemaVersion=1;files=$rows})
[pscustomobject]@{SourceFiles=$rows.Count;Manifest='source-manifest.json';Note='清单用于检测意外修改，不是数字签名或版权授权。'}
