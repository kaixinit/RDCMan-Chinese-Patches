#Requires -Version 5.1
[CmdletBinding()]
param([string]$PackagePath,[switch]$Download,[string]$PythonPath,[string]$CacheDirectory=(Join-Path $PSScriptRoot '.local\native-runtime'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scripts\Common.ps1')
Assert-WindowsPatchHost
Assert-SourceBundle $PSScriptRoot
$config=Read-PatchJson (Join-Path $PSScriptRoot 'patch.json')
$cache=Get-FullPatchPath $CacheDirectory
$destination=Join-Path $cache ('VC-'+$config.nativeRuntime.version+'-x86')
if(Test-Path -LiteralPath $destination){Assert-NativeRuntime $destination $config;return $destination}
if($PackagePath -and $Download){throw 'PackagePath 与 Download 不能同时使用。'}
if(-not $PackagePath -and -not $Download){throw '缺少固定版本的 x86 VC++ 运行库。可传入 -PackagePath，或显式使用 -Download。'}
$python=Get-PatchPython $PythonPath
[void][IO.Directory]::CreateDirectory($cache)
$stage=Join-Path $cache ('.runtime-stage-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($stage)
$success=$false
try {
    if($PackagePath){$package=(Resolve-Path -LiteralPath $PackagePath -ErrorAction Stop).Path}
    else {
        $package=Join-Path $stage 'VC_redist.x86.exe'
        [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $config.nativeRuntime.url -OutFile $package
    }
    if((Get-FileHash -LiteralPath $package).Hash -cne $config.nativeRuntime.packageSHA256){throw '微软 x86 运行库包 SHA256 不匹配。'}
    $signature=Get-AuthenticodeSignature -LiteralPath $package
    if($signature.Status.ToString() -cne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation'){throw '微软运行库包签名验证未通过。'}
    $product=Join-Path $stage 'product'
    Invoke-RuntimeTool $python @('extract','--package',$package,'--directory',$product,'--work',(Join-Path $stage 'cabinets'),'--report',(Join-Path $stage 'runtime-report.json'))
    Assert-NativeRuntime $product $config
    foreach($entry in $config.nativeRuntime.files){
        if((Get-AuthenticodeSignature -LiteralPath (Join-Path $product $entry.name)).Status.ToString() -cne 'Valid'){throw ('运行库 DLL 签名验证未通过：'+$entry.name)}
    }
    [IO.Directory]::Move($product,$destination)
    $success=$true
    return $destination
} catch {
    throw ('运行库准备失败，未执行安装程序。检查材料：'+$stage+'。原因：'+$_.Exception.Message)
} finally {
    if($success){
        $absolute=[IO.Path]::GetFullPath($stage)
        if([IO.Path]::GetDirectoryName($absolute) -cne [IO.Path]::GetFullPath($cache) -or [IO.Path]::GetFileName($absolute) -notmatch '^\.runtime-stage-[0-9a-f]{32}$'){throw '运行库临时目录清理边界失败。'}
        Remove-Item -LiteralPath $absolute -Recurse -Force
    }
}
