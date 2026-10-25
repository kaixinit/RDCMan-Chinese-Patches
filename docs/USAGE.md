# 使用步骤

所有命令在 Windows PowerShell 5.1 或 PowerShell 7 中执行。示例中的 `D:` 路径须按实际情况替换。首次使用前先查看根目录 README、NOTICE 和具体模块的 `patch.json`。

## 1. 准备原版与环境

1. 自行取得有权使用的受支持原版，不使用已经汉化的 EXE 作为输入。
2. 用 `Get-FileHash -Algorithm SHA256` 核对 [版本表](VERSIONS.md)。版本号相同但哈希不同也不支持，不应删除校验代码强行运行。
3. 2.93 需要 .NET Framework 4.8 及其 `csc.exe`；3.22 构建和复检需要 Python 3.9+，不需要额外 pip 包。脚本不安装 Python。
4. 把原版和将要生成的文件放在仓库外。输出目录必须尚不存在，输入原版不被覆盖。

## 2. 选择一个模块

下方三组命令相互独立。`Set-Location` 命令均从仓库根目录出发；运行另一组前先返回仓库根目录，或直接使用该模块的绝对路径。

### 2.93

```powershell
Set-Location .\patches\rdcman-2.93

.\Apply-RdcManPatch.ps1 -SourcePath 'D:\RDCMan-original\2.93\RDCMan.exe' -OutputDirectory 'D:\RDCMan-build\2.93-zh' -WhatIf
.\Apply-RdcManPatch.ps1 -SourcePath 'D:\RDCMan-original\2.93\RDCMan.exe' -OutputDirectory 'D:\RDCMan-build\2.93-zh' -DownloadDependency
.\Test-RdcManPatch.ps1 -OutputDirectory 'D:\RDCMan-build\2.93-zh'
```

最后手动打开输出目录中的 `RDCMan.exe`。

### 3.22 x64

```powershell
Set-Location .\patches\rdcman-3.22-x64

.\Apply-RdcManPatch.ps1 -SourcePath 'D:\RDCMan-original\3.22-x64\RDCMan.exe' -OutputDirectory 'D:\RDCMan-build\3.22-x64-zh' -WhatIf
.\Apply-RdcManPatch.ps1 -SourcePath 'D:\RDCMan-original\3.22-x64\RDCMan.exe' -OutputDirectory 'D:\RDCMan-build\3.22-x64-zh' -DownloadDependency
.\Test-RdcManPatch.ps1 -OutputDirectory 'D:\RDCMan-build\3.22-x64-zh'
```

最后手动打开输出目录中的 `RDCMan.exe`。未将 Python 加入 PATH 时，给构建和复检命令额外传入 `-PythonPath 'D:\Python311\python.exe'`。

### 3.22 x86

```powershell
Set-Location .\patches\rdcman-3.22-x86

.\Apply-RdcManPatch.ps1 -SourcePath 'D:\RDCMan-original\3.22-x86\RDCMan-x86.exe' -OutputDirectory 'D:\RDCMan-build\3.22-x86-zh' -WhatIf
.\Apply-RdcManPatch.ps1 -SourcePath 'D:\RDCMan-original\3.22-x86\RDCMan-x86.exe' -OutputDirectory 'D:\RDCMan-build\3.22-x86-zh' -DownloadDependency
.\Test-RdcManPatch.ps1 -OutputDirectory 'D:\RDCMan-build\3.22-x86-zh'
```

这里的下载参数会同时准备 Mono.Cecil 和固定版本的微软 x86 VC++ 运行库。运行库包只提取，不执行安装器。

最后直接打开输出目录中的 `RDCMan-x86.exe`，或用 `启动中文版.cmd`；默认使用 RDCore，不需要 `-mstsc` 参数。另有可选的 `启动兼容模式.cmd`，使用程序原有 MSTSC 模式。

## 3. 离线构建

在可联网电脑从官方来源取得固定依赖包，再转移到目标电脑。不要将依赖包加入 Git 仓库。

2.93 和 x64：将上方构建命令的 `-DownloadDependency` 换为：

```powershell
-CecilPackagePath 'D:\Packages\mono.cecil.0.11.6.nupkg'
```

此行是追加参数示意，不能单独作为命令执行。x86 的完整离线示例：

```powershell
.\Apply-RdcManPatch.ps1 -SourcePath 'D:\RDCMan-original\3.22-x86\RDCMan-x86.exe' -OutputDirectory 'D:\RDCMan-build\3.22-x86-zh' -CecilPackagePath 'D:\Packages\mono.cecil.0.11.6.nupkg' -VCRuntimePackagePath 'D:\Packages\VC_redist.x86.exe'
```

依赖的精确版本、包地址和哈希见模块 `patch.json`。同名的新版 VC++ 安装包可能不匹配，不能替换固定依赖。缓存默认在模块的 `.local` 目录，已被 Git 忽略；生成和打包脚本不会把缓存加入源码 ZIP。

## 4. 生成结果与复检

生成目录至少包含汉化 EXE、`backup/RDCMan.original.exe` 和 `patch-report.json`。2.93 的构建和复检会执行 28 项不调用程序入口的运行检查；3.22 复检核对单文件包、261 项原有捆绑文件、宿主和资源，x86 还验证 7 项原生依赖。

这些是本地生成的文件，不能作为源码包提交。修改副本的原版数字签名会失效，输入原版及其备份保持原始字节。

首次启动时可能出现版本配置兼容提醒。汉化只改变提示语言，不删除未知配置或跳过警告。已有用户应先备份连接文件，再决定是否用旧版本保存。

## 5. 恢复独立副本

正常退出对应程序，在同一模块目录中运行，替换示例输出路径：

```powershell
.\Restore-RdcManPatch.ps1 -OutputDirectory 'D:\RDCMan-build\2.93-zh' -WhatIf
.\Restore-RdcManPatch.ps1 -OutputDirectory 'D:\RDCMan-build\2.93-zh'
```

只恢复这个输出目录中的程序；汉化文件另存为 `.bak`，不覆盖最初的输入路径，不改连接文件、密码或偏好设置。备份损坏、目标有额外修改或仍在运行时会拒绝操作。

## 6. 常见问题

- **禁止运行脚本**：按设备或组织政策处理，先审核脚本。项目不自动改变执行策略、不绕过组织限制、不自动解除下载文件的阻止标记。
- **原版哈希不匹配**：核对版本、架构与是否误选汉化副本；不要删掉哈希检查。
- **Python 不可用**：确认安装 3.9+，重新打开 PowerShell，或使用 `-PythonPath`。Microsoft Store 的占位别名不作为解释器执行。
- **依赖下载失败**：使用离线固定包。包和 DLL 的哈希检查仍会执行。
- **输出目录已存在**：指定新目录，不把已有原版或旧汉化目录当成输出目标。
- **启动的还是旧界面**：检查快捷方式是否指向刚生成的目录。
- **构建中断**：临时 `.rdcman-patch-*` 目录中可能有完整程序和提取文件；不要将它提交到 GitHub。
- **反馈问题**：提供模块名、补丁版本、PowerShell 版本和简短复现步骤；不要附带真实 `.rdg`、账号、密码或完整个人日志。
