# 使用指南

## 准备

- 使用 Windows PowerShell 5.1 或 PowerShell 7。
- 准备有权使用且 SHA256 匹配的原版，详见[版本与校验值](VERSIONS.md)。[微软官方页面](https://learn.microsoft.com/en-us/sysinternals/downloads/rdcman)可能只提供当前版本，本项目不提供旧版镜像。
- 2.93 需要 .NET Framework 4.8；3.22 需要 Python 3.9+，无需额外 pip 包。
- 完整解压源码。原版和生成目录放在仓库外，生成目录必须尚不存在。

## 选择模块

在仓库根目录打开 PowerShell，按需要选择一组命令。输入原版完整路径时无需加引号；如桌面已有同名输出目录，请修改 `$output` 的文件夹名称。

### RDCMan 2.93

```powershell
Set-Location .\patches\rdcman-2.93
$source = Read-Host '原版 RDCMan.exe 的完整路径'
$output = Join-Path ([Environment]::GetFolderPath('Desktop')) 'RDCMan-2.93-zh'
```

### RDCMan 3.22 x64

```powershell
Set-Location .\patches\rdcman-3.22-x64
$source = Read-Host '原版 x64 RDCMan.exe 的完整路径'
$output = Join-Path ([Environment]::GetFolderPath('Desktop')) 'RDCMan-3.22-x64-zh'
```

### RDCMan 3.22 x86

```powershell
Set-Location .\patches\rdcman-3.22-x86
$source = Read-Host '原版 RDCMan-x86.exe 的完整路径'
$output = Join-Path ([Environment]::GetFolderPath('Desktop')) 'RDCMan-3.22-x86-zh'
```

上面三组命令均从仓库根目录出发，选择一组后继续下方步骤。切换模块时请先返回仓库根目录，或重新打开 PowerShell。

## 生成并复检

在所选模块目录执行：

```powershell
# 检查原版和目标路径，不生成程序
.\Apply-RdcManPatch.ps1 -SourcePath $source -OutputDirectory $output -WhatIf

# 准备固定依赖并生成中文副本
.\Apply-RdcManPatch.ps1 -SourcePath $source -OutputDirectory $output -DownloadDependency

# 检查生成结果
.\Test-RdcManPatch.ps1 -OutputDirectory $output
```

`-DownloadDependency` 显式允许从固定来源获取依赖。x86 会同时准备指定版本的 VC++ 运行库，仅提取文件，不执行安装器。脚本不会下载 RDCMan 或启动远程连接。

生成后，2.93 和 x64 的入口为 `RDCMan.exe`，x86 为 `RDCMan-x86.exe`。x86 默认使用 RDCore；`启动兼容模式.cmd` 是可选的 MSTSC 入口。

3.22 未能自动找到 Python 时，可指定已安装解释器的位置：

```powershell
$python = Read-Host 'python.exe 的完整路径'
.\Apply-RdcManPatch.ps1 -SourcePath $source -OutputDirectory $output -DownloadDependency -PythonPath $python
.\Test-RdcManPatch.ps1 -OutputDirectory $output -PythonPath $python
```

## 离线构建

在可联网的电脑从官方来源取得模块要求的固定依赖包，再复制到目标电脑。包名相同不代表版本和哈希相同，精确信息见各模块的 `patch.json` 和[第三方说明](../THIRD_PARTY_NOTICES.md)。

2.93 和 x64 在设置好 `$source`、`$output` 后执行：

```powershell
$cecilPackage = Read-Host 'mono.cecil.0.11.6.nupkg 的完整路径'
.\Apply-RdcManPatch.ps1 -SourcePath $source -OutputDirectory $output -CecilPackagePath $cecilPackage
.\Test-RdcManPatch.ps1 -OutputDirectory $output
```

x86 还需要固定版本的微软运行库包：

```powershell
$cecilPackage = Read-Host 'mono.cecil.0.11.6.nupkg 的完整路径'
$runtimePackage = Read-Host '指定版本 VC_redist.x86.exe 的完整路径'
.\Apply-RdcManPatch.ps1 -SourcePath $source -OutputDirectory $output -CecilPackagePath $cecilPackage -VCRuntimePackagePath $runtimePackage
.\Test-RdcManPatch.ps1 -OutputDirectory $output
```

3.22 的离线构建同样需要事先安装 Python。依赖默认缓存在模块的 `.local` 目录。

## 恢复英文副本

先正常退出输出目录中的程序，在对应模块目录执行；若新开了 PowerShell，先重新设置 `$output` 为此前生成的目录。

```powershell
.\Restore-RdcManPatch.ps1 -OutputDirectory $output -WhatIf
.\Restore-RdcManPatch.ps1 -OutputDirectory $output
```

恢复工具使用 `backup/RDCMan.original.exe`，仅恢复指定输出目录中的程序，并另存汉化副本。原始输入路径、连接文件和个人设置不会被修改。不要删除原版备份或手工改写构建报告。

## 常见问题

| 问题 | 处理方式 |
|---|---|
| 原版哈希不匹配 | 核对版本、架构及是否误选汉化文件，不跳过校验 |
| 输出目录已存在 | 为 `$output` 选择一个新目录 |
| 找不到 Python | 安装 Python 3.9+ 或指定 `-PythonPath` |
| 下载依赖失败 | 使用匹配版本的离线包，仍需通过哈希校验 |
| 禁止运行脚本 | 按设备或组织政策处理，先审核脚本；项目不自动修改执行策略 |
| 仍显示旧界面 | 检查快捷方式是否指向新生成的目录 |
| 未知 XML 节点或版本兼容提醒 | 先备份配置和连接文件，再决定是否继续保存 |

本地生成的 EXE、原版备份、依赖缓存和个人配置均不属于源码发布内容。修改后的副本不再具有原版有效数字签名。
