#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$DestinationZip)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scripts\Common.ps1')
Assert-SourceBundle $PSScriptRoot
$destination=Get-FullPatchPath $DestinationZip
if([IO.File]::Exists($destination) -or [IO.Directory]::Exists($destination)){throw '打包目标已存在，拒绝覆盖。'}
$manifest=Read-PatchJson (Join-Path $PSScriptRoot 'source-manifest.json')
$files=@($manifest.files.path)+@('source-manifest.json')
$allowedExtensions=@('.ps1','.cs','.json','.md','.tsv')
foreach($relative in $files){
    $path=Join-Path $PSScriptRoot $relative
    if($relative -notin @('.gitignore','.gitattributes') -and [IO.Path]::GetExtension($relative) -notin $allowedExtensions){throw ('不允许打包的文件类型：'+$relative)}
    $bytes=[IO.File]::ReadAllBytes($path)
    if(($bytes.Length -ge 2 -and $bytes[0] -eq 77 -and $bytes[1] -eq 90) -or $relative -match '\.(exe|dll|pdb|rdg|settings|nupkg|bak)(\.|$)'){throw ('打包中检测到程序或私人数据：'+$relative)}
    $text=[Text.Encoding]::UTF8.GetString($bytes)
    if($text -match '(?i)[A-Z]:[\\/]Users[\\/][^\r\n"\s<>]+'){throw ('源文件包含用户绝对路径：'+$relative)}
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$parent=[IO.Path]::GetDirectoryName($destination)
if(-not [IO.Directory]::Exists($parent)){throw 'ZIP 的父目录必须已存在。'}
$archive=$null
try {
    $archive=[IO.Compression.ZipFile]::Open($destination,[IO.Compression.ZipArchiveMode]::Create)
    foreach($relative in $files){
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $PSScriptRoot $relative),('RDCMan-2.93-zh-patch/'+$relative.Replace('\','/')),[IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {if($archive){$archive.Dispose()}}
[pscustomobject]@{Zip=$destination;Files=$files.Count;ContainsRdcManBinaries=$false;SHA256=(Get-FileHash -LiteralPath $destination).Hash}
