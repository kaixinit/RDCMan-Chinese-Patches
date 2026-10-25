#Requires -Version 5.1
[CmdletBinding()]
param([string]$PackagePath,[switch]$Download,[string]$CacheDirectory=(Join-Path $PSScriptRoot '.local\dependencies'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scripts\Common.ps1')
Assert-WindowsPatchHost
Assert-SourceBundle $PSScriptRoot
$config=Read-PatchJson (Join-Path $PSScriptRoot 'patch.json')
$framework=if($PSVersionTable.PSEdition -eq 'Desktop'){'net40'}else{'netstandard2.0'}
$dllHash=if($framework -eq 'net40'){$config.dependency.net40SHA256}else{$config.dependency.netstandard20SHA256}
$cache=Get-FullPatchPath $CacheDirectory
$destination=Join-Path $cache ('Mono.Cecil-'+$config.dependency.version+'\'+$framework+'\Mono.Cecil.dll')
if([IO.File]::Exists($destination)){
    if((Get-FileHash -LiteralPath $destination).Hash -cne $dllHash){throw '缓存中的 Mono.Cecil 校验失败，请使用新的缓存目录。'}
    return $destination
}
if($PackagePath -and $Download){throw 'PackagePath 与 Download 不能同时使用。'}
if(-not $PackagePath -and -not $Download){throw '缺少依赖。可用 -Download 从 NuGet 下载固定版本，或用 -PackagePath 指定离线 nupkg。'}
$temporary=$null
try {
    if($PackagePath){$package=(Resolve-Path -LiteralPath $PackagePath -ErrorAction Stop).Path}
    else {
        [IO.Directory]::CreateDirectory($cache) | Out-Null
        $temporary=Join-Path $cache ('download-'+[Guid]::NewGuid().ToString('N')+'.nupkg')
        [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $config.dependency.url -OutFile $temporary
        $package=$temporary
    }
    if((Get-FileHash -LiteralPath $package).Hash -cne $config.dependency.packageSHA256){throw 'NuGet 包 SHA256 不匹配，依赖未载入。'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($package)
    try {
        $entry=$archive.GetEntry('lib/'+$framework+'/Mono.Cecil.dll')
        if($null -eq $entry){throw 'NuGet 包缺少预期依赖文件。'}
        $memory=[IO.MemoryStream]::new()
        $stream=$entry.Open()
        try {$stream.CopyTo($memory);$dllBytes=$memory.ToArray()} finally {$stream.Dispose();$memory.Dispose()}
    } finally {$archive.Dispose()}
    if((Get-BytesSHA256 $dllBytes) -cne $dllHash){throw 'Mono.Cecil.dll SHA256 不匹配。'}
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    if([IO.File]::Exists($destination)){throw '依赖目标在准备期间被创建，已停止以避免覆盖。'}
    $file=[IO.File]::Open($destination,[IO.FileMode]::CreateNew)
    try {$file.Write($dllBytes,0,$dllBytes.Length)} finally {$file.Dispose()}
    return $destination
} finally {if($temporary -and [IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
