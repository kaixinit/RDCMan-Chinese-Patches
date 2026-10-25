#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$rootPrefix=$repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
$manifestFile=Join-Path $repoRoot 'source-manifest.json'
if(-not [IO.File]::Exists($manifestFile)){throw '缺少合集清单，请重新解压完整源码包。'}
$manifest=[IO.File]::ReadAllText($manifestFile,[Text.Encoding]::UTF8) | ConvertFrom-Json
if($manifest.schemaVersion -ne 1){throw '不支持的合集清单版本。'}
$allowed=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$textExtensions=@('.ps1','.py','.cs','.json','.md','.tsv','.yml')
$decoder=[Text.UTF8Encoding]::new($false,$true)
foreach($entry in $manifest.files){
 $relative=[string]$entry.path
 if([IO.Path]::IsPathRooted($relative) -or $relative.Contains(':') -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or $relative.Contains('\')){throw '清单中含非法相对路径。'}
 if(-not $allowed.Add($relative)){throw ('清单路径重复：'+$relative)}
 $path=[IO.Path]::GetFullPath((Join-Path $repoRoot $relative))
 if(-not $path.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)){throw '清单路径超出仓库。'}
 if(-not [IO.File]::Exists($path)){throw ('缺少源文件：'+$relative)}
 $item=Get-Item -LiteralPath $path
 if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw ('不发布链接文件：'+$relative)}
 if($item.Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $entry.sha256){throw ('源文件与清单不一致：'+$relative)}
 $leaf=[IO.Path]::GetFileName($relative)
 if($leaf -notin @('.gitignore','.gitattributes') -and [IO.Path]::GetExtension($relative) -notin $textExtensions){throw ('不允许发布的文件类型：'+$relative)}
 if($relative -match '(?i)\.(exe|dll|pdb|nupkg|zip|7z|rar|cab|msi|bak|rdg|settings|config|pem|key)(\.|$)'){throw ('检测到程序、归档或个人配置：'+$relative)}
 $bytes=[IO.File]::ReadAllBytes($path)
 if($bytes.Length -ge 2 -and $bytes[0] -eq 77 -and $bytes[1] -eq 90){throw ('检测到程序头：'+$relative)}
 try {$text=$decoder.GetString($bytes)} catch {throw ('不是有效 UTF-8 文本：'+$relative)}
 if($text.IndexOf([char]0) -ge 0){throw ('检测到非文本数据：'+$relative)}
 if($text -match '(?i)[A-Z]:[\\/]Users[\\/][^\r\n"\s<>]+'){throw ('检测到用户绝对路径：'+$relative)}
}
[void]$allowed.Add('source-manifest.json')
$ignored=0
foreach($file in @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force)){
 $relative=$file.FullName.Substring($rootPrefix.Length).Replace('\','/')
 if($allowed.Contains($relative)){continue}
 if($relative -match '(^|/)(\.git|\.local|__pycache__|build|dist|backup|backups|\.rdcman-patch-[^/]+|\.runtime-stage-[^/]+|\.dependency-stage-[^/]+)(/|$)'){$ignored++;continue}
 throw ('出现未列入发布清单的文件，请移到仓库外或按维护流程处理：'+$relative)
}
$repository=[IO.File]::ReadAllText((Join-Path $repoRoot 'repository.json'),[Text.Encoding]::UTF8) | ConvertFrom-Json
$modules=@($repository.modules)
if($modules.Count -ne 3){throw '合集必须包含三个指定补丁模块。'}
foreach($module in $modules){
 $moduleRoot=Join-Path $repoRoot $module.directory
 & {
  param($moduleRoot,$module)
  . (Join-Path $moduleRoot 'scripts/Common.ps1')
  Assert-SourceBundle $moduleRoot
  $config=Read-PatchJson (Join-Path $moduleRoot 'patch.json')
  if($config.packageVersion -cne $module.patchVersion -or $config.sourceSHA256 -cne $module.sourceSHA256 -or $config.targetVersion -cne $module.targetVersion){throw '模块配置与合集版本索引不一致。'}
  Assert-TranslationData (Join-Path $moduleRoot 'patches/translations.json') $config.fixedTextOccurrences
 } $moduleRoot $module
}
[pscustomobject]@{Passed=$true;SourceFiles=$allowed.Count;Modules=$modules.Count;IgnoredLocalFiles=$ignored;ContainsApplicationBinaries=$false;NoApplicationStarted=$true}
