# RDCMan 2.93 中文补丁

补丁版本：**0.1.5**。软件版本：**2.93.1431.0**。汉化作者：**kaixinit**。

本目录只包含补丁源码、译表和说明，不提供原版或汉化 EXE、DLL、安装包和个人配置。许可边界见 [NOTICE.md](NOTICE.md)，完整合集说明见 [根 README](../../README.md)。

## 适用输入

- Windows、PowerShell 5.1 或 PowerShell 7。
- .NET Framework 4.8，含系统 csc.exe。2.93 补丁不需要 Python。
- 自行取得且有权使用的未修改原版 `RDCMan.exe`；哈希必须精确匹配：

```text
D11CF847DF9DAC6EDA1891022986729EFE690B3DB8E6F876BEF4E7A6AFFFC759
```

不支持其他构建、架构或已汉化文件；即使版本号相同也不能跳过哈希检查。本模块的构建代码通过相对路径定位自身文件，可独立执行，不依赖其他补丁目录。

## 生成和复检

在本目录打开 PowerShell。下方路径是示例，输出目录须位于仓库外且尚不存在。

```powershell
.\Apply-RdcManPatch.ps1 -SourcePath 'D:\RDCMan-original\2.93\RDCMan.exe' -OutputDirectory 'D:\RDCMan-build\2.93-zh' -WhatIf
.\Apply-RdcManPatch.ps1 -SourcePath 'D:\RDCMan-original\2.93\RDCMan.exe' -OutputDirectory 'D:\RDCMan-build\2.93-zh' -DownloadDependency
.\Test-RdcManPatch.ps1 -OutputDirectory 'D:\RDCMan-build\2.93-zh'
```

`-DownloadDependency` 显式允许获取固定构建依赖；脚本不下载 RDCMan。输入原版不被覆盖；构建不启动程序、不连接服务器、不代为接受许可、不更改执行策略和实际偏好设置。

## 离线构建

```powershell
.\Apply-RdcManPatch.ps1 -SourcePath 'D:\RDCMan-original\2.93\RDCMan.exe' -OutputDirectory 'D:\RDCMan-build\2.93-zh' -CecilPackagePath 'D:\Packages\mono.cecil.0.11.6.nupkg'
```

固定依赖的来源、哈希及缓存见 [依赖说明](docs/依赖说明.md)。依赖缓存和提取文件都不属于源码发布内容。

## 输出与恢复

本地生成 `RDCMan.exe`、`backup/RDCMan.original.exe` 和 `patch-report.json`，这些文件不提交到 GitHub。先正常退出输出副本，再按需恢复：

```powershell
.\Restore-RdcManPatch.ps1 -OutputDirectory 'D:\RDCMan-build\2.93-zh' -WhatIf
.\Restore-RdcManPatch.ps1 -OutputDirectory 'D:\RDCMan-build\2.93-zh'
```

恢复仅操作这个独立输出目录，汉化文件另存为 `.bak`；原始输入、个人连接配置和密码不受脚本修改。目标有额外修改或仍在运行时会拒绝恢复。

## 当前内容

- 604 处固定文字、496 种英文原文；另处理动态显示名称。
- 保留菜单、右键、启动提示、尺寸标签、关于窗口排版及无效范围导入校验修复。
- 关于窗口显示“汉化作者：kaixinit”，保留微软版权、原作者、官网；现有产品属性和独立配置目录不变。
- 构建校验仅修改记录的文字与限定方法，保留资源、引用及内部标识。验证范围与记录见 [验证记录](docs/验证记录.md)。

实际系统组件或远端提示仍可能使用原语言，尚未覆盖真实远程连接和全部 DPI。

更多命令与常见问题见 [合集使用步骤](../../docs/USAGE.md)，修改补丁前阅读 [维护说明](docs/维护说明.md)。
