# RDCMan 3.22 x86 中文补丁

补丁版本 **0.1.4**，适用于 **3.22.0.0** 的指定原版。完整使用步骤见[使用指南](../../docs/USAGE.md)。

## 环境与原版

- Windows、Windows PowerShell 5.1 或 PowerShell 7。
- Python 3.9+。
- 自行取得有权使用的原版 `RDCMan-x86.exe`，SHA256 必须匹配：

```text
07D5E675CE5C91F5A7859CEA14F7D97797F3644B4222B6BF9E44E4B0FBC5B1BF
```

## 生成中文副本

在本模块目录打开 PowerShell，输入原版完整路径，无需加引号。输出目录必须尚不存在。

```powershell
$source = Read-Host '原版 RDCMan-x86.exe 的完整路径'
$output = Join-Path ([Environment]::GetFolderPath('Desktop')) 'RDCMan-3.22-x86-zh'

.\Apply-RdcManPatch.ps1 -SourcePath $source -OutputDirectory $output -WhatIf
.\Apply-RdcManPatch.ps1 -SourcePath $source -OutputDirectory $output -DownloadDependency
.\Test-RdcManPatch.ps1 -OutputDirectory $output
```

完成后手动打开输出目录中的 `RDCMan-x86.exe`。在线命令只下载固定构建依赖；离线依赖与版本校验见[依赖说明](docs/依赖说明.md)。

## 恢复

正常退出生成的程序，再执行：

```powershell
.\Restore-RdcManPatch.ps1 -OutputDirectory $output -WhatIf
.\Restore-RdcManPatch.ps1 -OutputDirectory $output
```

恢复仅针对这个输出目录。请保留原版备份和构建报告；脚本不修改原始输入、连接文件或个人设置。

功能变化见[更新记录](CHANGELOG.md)，验证范围见[验证说明](docs/验证记录.md)。本模块仅发布补丁源码，版权信息见 [NOTICE.md](NOTICE.md)。
