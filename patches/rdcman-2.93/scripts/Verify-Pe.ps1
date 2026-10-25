param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$TargetPath,[Parameter(Mandatory=$true)][string]$ReportPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
function Read-PeResources([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    if($bytes.Length -lt 256 -or $bytes[0] -ne 77 -or $bytes[1] -ne 90){throw '无效的 PE 文件。'}
    $pe=[BitConverter]::ToInt32($bytes,0x3c)
    $sections=[BitConverter]::ToUInt16($bytes,$pe+6)
    $optionalSize=[BitConverter]::ToUInt16($bytes,$pe+20)
    $optional=$pe+24
    $magic=[BitConverter]::ToUInt16($bytes,$optional)
    $dataDirectory=if($magic -eq 0x10b){$optional+96}elseif($magic -eq 0x20b){$optional+112}else{throw '未知 PE 格式。'}
    $sectionRows=@(for($i=0;$i -lt $sections;$i++){
        $off=$optional+$optionalSize+40*$i
        [pscustomobject]@{VA=[BitConverter]::ToUInt32($bytes,$off+12);Span=[Math]::Max([BitConverter]::ToUInt32($bytes,$off+8),[BitConverter]::ToUInt32($bytes,$off+16));Raw=[BitConverter]::ToUInt32($bytes,$off+20)}
    })
    function Resolve-Rva([uint32]$Rva) {
        foreach($section in $sectionRows){if($Rva -ge $section.VA -and $Rva -lt ($section.VA+$section.Span)){return [int]($section.Raw+$Rva-$section.VA)}}
        throw '资源 RVA 越界。'
    }
    $base=Resolve-Rva ([BitConverter]::ToUInt32($bytes,$dataDirectory+16))
    $result=@{}
    function Walk-Resource([int]$Relative,[string[]]$Parts,[int]$Depth) {
        if($Depth -gt 8){throw '资源目录层数异常。'}
        $table=$base+$Relative
        $count=[int][BitConverter]::ToUInt16($bytes,$table+12)+[int][BitConverter]::ToUInt16($bytes,$table+14)
        for($i=0;$i -lt $count;$i++){
            $name=[BitConverter]::ToUInt32($bytes,$table+16+8*$i)
            $target=[BitConverter]::ToUInt32($bytes,$table+20+8*$i)
            if(($name -band [uint32]2147483648) -ne 0){
                $position=$base+($name -band 2147483647)
                $length=[BitConverter]::ToUInt16($bytes,$position)
                $label=[Text.Encoding]::Unicode.GetString($bytes,$position+2,2*$length)
            }else{$label=[string]$name}
            $path=@($Parts)+@($label)
            if(($target -band [uint32]2147483648) -ne 0){Walk-Resource ($target -band 2147483647) $path ($Depth+1)}
            else {
                $payloadRva=[BitConverter]::ToUInt32($bytes,$base+$target)
                $size=[BitConverter]::ToUInt32($bytes,$base+$target+4)
                $position=Resolve-Rva $payloadRva
                $payload=[byte[]]::new($size)
                [Array]::Copy($bytes,$position,$payload,0,$size)
                $result[$path -join '/']=[pscustomobject]@{Bytes=$size;SHA256=(Get-BytesSHA256 $payload)}
            }
        }
    }
    Walk-Resource 0 @() 0
    return [pscustomobject]@{Resources=$result;CertificateOffset=[BitConverter]::ToUInt32($bytes,$dataDirectory+32);CertificateSize=[BitConverter]::ToUInt32($bytes,$dataDirectory+36);Machine=[BitConverter]::ToUInt16($bytes,$pe+4)}
}
$original=Read-PeResources $SourcePath
$localized=Read-PeResources $TargetPath
if($original.Resources.Count -ne $localized.Resources.Count -or $original.Machine -ne $localized.Machine){throw 'PE 结构或资源数量改变。'}
foreach($key in $original.Resources.Keys){
    if(-not $localized.Resources.ContainsKey($key) -or $original.Resources[$key].SHA256 -cne $localized.Resources[$key].SHA256){throw ('Windows 资源改变：'+$key)}
}
if($original.CertificateSize -le 0 -or $localized.CertificateOffset -ne 0 -or $localized.CertificateSize -ne 0){throw '副本签名目录状态异常。'}
$report=[ordered]@{Passed=$true;NativeResourcesUnchanged=$original.Resources.Count;MachineUnchanged=$true;ModifiedCopyUnsigned=$true;SourceSHA256=(Get-FileHash -LiteralPath $SourcePath).Hash;TargetSHA256=(Get-FileHash -LiteralPath $TargetPath).Hash}
Write-PatchJson $ReportPath $report
$report
