Set-StrictMode -Version 2.0

function Get-BytesSHA256([byte[]]$Bytes) {
    $hash=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-','') }
    finally { $hash.Dispose() }
}
function Read-PatchJson([string]$Path) {
    return ([IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8) | ConvertFrom-Json)
}
function Write-PatchJson([string]$Path,$Value) {
    [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
}
function Get-PatchRoot { return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')) }
function Get-FullPatchPath([string]$Path) {
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}
function Assert-WindowsPatchHost {
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw '此脚本仅支持 Windows。'}
    if($PSVersionTable.PSVersion -lt [version]'5.1'){throw '需要 PowerShell 5.1 或更新版本。'}
}
function Assert-SourceBundle([string]$Root) {
    $path=Join-Path $Root 'source-manifest.json'
    if(-not [IO.File]::Exists($path)){throw '缺少源文件清单，请重新解压补丁包。'}
    $manifest=Read-PatchJson $path
    foreach($entry in $manifest.files){
        if([IO.Path]::IsPathRooted($entry.path) -or $entry.path -match '(^|[\\/])\.\.([\\/]|$)'){throw '源文件清单含越界路径。'}
        $candidate=Join-Path $Root $entry.path
        if(-not [IO.File]::Exists($candidate) -or (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -cne $entry.sha256){
            throw ('补丁源文件已改变或缺失：'+$entry.path+'。维护者修改后需重新生成 source-manifest.json。')
        }
    }
}
function Assert-TargetNotRunning([string]$Executable) {
    $full=[IO.Path]::GetFullPath($Executable)
    foreach($process in @(Get-Process -Name RDCMan -ErrorAction SilentlyContinue)){
        try { $runningPath=$process.Path } catch { continue }
        if($runningPath -and [string]::Equals($runningPath,$full,[StringComparison]::OrdinalIgnoreCase)){
            throw '目标副本正在运行，请正常退出该副本后重试；脚本不会结束进程。'
        }
    }
}
function Assert-TranslationData([string]$Path,[int]$Count) {
    $rows=@(Read-PatchJson $Path)
    if($rows.Count -ne $Count){throw '翻译条目数量与 patch.json 不一致。'}
    $seen=@{}
    foreach($row in $rows){
        $key=$row.Method+'|'+$row.Index
        if($seen.ContainsKey($key)){throw ('重复补丁位置：'+$key)}
        $seen[$key]=$true
        if($row.Type -notlike 'RdcMan.*' -or $row.Index -lt 0){throw '补丁位置无效。'}
        $old=[Collections.Generic.List[string]]::new()
        $new=[Collections.Generic.List[string]]::new()
        foreach($match in [regex]::Matches($row.English,'\{\d+(?:[^{}]*)\}')){$old.Add($match.Value)}
        foreach($match in [regex]::Matches($row.Chinese,'\{\d+(?:[^{}]*)\}')){$new.Add($match.Value)}
        $old.Sort();$new.Sort()
        if(($old -join '|') -cne ($new -join '|')){throw ('格式占位符不一致：'+$row.Id)}
    }
}
function Invoke-PatchRuntimeChecks([string]$Root,[string]$Executable,[string]$ReportPath,[string]$WorkDirectory) {
    $candidates=@(
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    )
    $compiler=$candidates | Where-Object {[IO.File]::Exists($_)} | Select-Object -First 1
    if(-not $compiler){throw '找不到 .NET Framework 4.x 的 csc.exe，请安装或修复 .NET Framework 4.8。'}
    $runner=Join-Path $WorkDirectory ('RuntimeChecks-'+[Guid]::NewGuid().ToString('N')+'.exe')
    try {
        $arguments=@('/nologo','/target:exe','/codepage:65001',('/out:'+$runner),'/reference:System.Xml.dll','/reference:System.Web.Extensions.dll',(Join-Path $Root 'tests\RuntimeChecks.cs'))
        $compileLog=@(& $compiler @arguments 2>&1)
        if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($runner)){throw ('检查程序编译失败：'+($compileLog -join [Environment]::NewLine))}
        $runLog=@(& $runner $Executable $ReportPath 2>&1)
        if($LASTEXITCODE -ne 0){throw ('运行检查未通过：'+($runLog -join [Environment]::NewLine))}
        $result=Read-PatchJson $ReportPath
        if(-not $result.Passed -or $result.Cases -ne 28 -or $result.TargetSHA256 -cne (Get-FileHash -LiteralPath $Executable).Hash){throw '运行检查结果无效。'}
        return $result
    } finally {
        if([IO.File]::Exists($runner)){[IO.File]::Delete($runner)}
    }
}
