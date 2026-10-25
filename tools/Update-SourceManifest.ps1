#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$config=[IO.File]::ReadAllText((Join-Path $repoRoot 'repository.json'),[Text.Encoding]::UTF8) | ConvertFrom-Json
$sourcePaths=@(
 '.gitignore','.gitattributes','.github/ISSUE_TEMPLATE/bug_report.yml',
 'README.md','NOTICE.md','LICENSE.md','THIRD_PARTY_NOTICES.md','CHANGELOG.md','repository.json',
 'Package-Source.ps1','tools/Test-Source.ps1','tools/Update-SourceManifest.ps1',
 'docs/USAGE.md','docs/VERSIONS.md','docs/GITHUB.md','docs/VALIDATION.md'
)
foreach($module in $config.modules){
 $moduleRoot=Join-Path $repoRoot $module.directory
 & (Join-Path $moduleRoot 'Update-SourceManifest.ps1') | Out-Null
 $moduleManifest=[IO.File]::ReadAllText((Join-Path $moduleRoot 'source-manifest.json'),[Text.Encoding]::UTF8) | ConvertFrom-Json
 foreach($entry in $moduleManifest.files){$sourcePaths+=($module.directory+'/'+$entry.path.Replace('\','/'))}
 $sourcePaths+=($module.directory+'/source-manifest.json')
}
$rows=@(foreach($relative in @($sourcePaths | Sort-Object -Unique)){
 $path=Join-Path $repoRoot $relative
 if(-not [IO.File]::Exists($path)){throw ('缺少允许发布的源文件：'+$relative)}
 [pscustomobject]@{path=$relative;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $path).Length}
})
$result=[ordered]@{schemaVersion=1;collectionVersion=$config.collectionVersion;files=$rows}
[IO.File]::WriteAllText((Join-Path $repoRoot 'source-manifest.json'),($result | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{SourceFiles=$rows.Count;Manifest='source-manifest.json';Note='清单用于检测字节变化，不是数字签名或版权授权。'}
