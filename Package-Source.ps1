#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$DestinationZip)
$ErrorActionPreference='Stop'
$repoRoot=[IO.Path]::GetFullPath($PSScriptRoot)
$destination=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationZip)
$rootPrefix=$repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
if($destination.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'ZIP 目标必须位于仓库外，避免成品混入源码目录。'}
if(Test-Path -LiteralPath $destination){throw 'ZIP 目标已存在，拒绝覆盖。'}
if(-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($destination))){throw 'ZIP 的父目录必须已存在。'}
$check=& (Join-Path $repoRoot 'tools/Test-Source.ps1')
if(-not $check.Passed){throw '源码检查未通过。'}
$manifest=[IO.File]::ReadAllText((Join-Path $repoRoot 'source-manifest.json'),[Text.Encoding]::UTF8) | ConvertFrom-Json
$files=@($manifest.files.path)+@('source-manifest.json')
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=$null
try {
 $archive=[IO.Compression.ZipFile]::Open($destination,[IO.Compression.ZipArchiveMode]::Create)
 foreach($relative in $files){
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $repoRoot $relative),('RDCMan-Chinese-Patches/'+$relative),[IO.Compression.CompressionLevel]::Optimal) | Out-Null
 }
} finally {if($archive){$archive.Dispose()}}
[pscustomobject]@{Zip=$destination;Files=$files.Count;ContainsApplicationBinaries=$false;SHA256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash}
