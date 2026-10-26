# RDCMan 中文补丁

[下载源码](https://github.com/kaixinit/RDCMan-Chinese-Patches/releases/latest) · [使用指南](docs/USAGE.md) · [版本与校验值](docs/VERSIONS.md) · [更新记录](CHANGELOG.md)

为 RDCMan 2.93 和 3.22 提供中文界面及常用界面修复。使用者自行准备匹配的微软原版，通过脚本在本地生成中文副本。

本项目仅发布补丁源码，不提供原版或汉化成品下载。项目由 **kaixinit** 维护，与 Microsoft、Sysinternals 无隶属关系。

## 支持版本

| 软件 | 补丁版本 | 模块 | 额外环境 |
|---|---|---|---|
| RDCMan 2.93.1431.0 | 0.1.5 | [2.93](patches/rdcman-2.93/README.md) | .NET Framework 4.8 |
| RDCMan 3.22.0.0 x64 | 0.1.3 | [3.22 x64](patches/rdcman-3.22-x64/README.md) | Python 3.9+ |
| RDCMan 3.22.0.0 x86 | 0.1.4 | [3.22 x86](patches/rdcman-3.22-x86/README.md) | Python 3.9+、固定版本的 x86 VC++ 依赖 |

三个模块均在 Windows 下使用，支持 Windows PowerShell 5.1 或 PowerShell 7。脚本校验原版 SHA256；仅版本号相同不足以确认兼容，请先核对[版本表](docs/VERSIONS.md)。

## 主要功能

- 菜单、右键、内置分组和常用提示的中文显示。
- 改善尺寸选项、分辨率按钮及关于窗口的排版。
- 将启动配置兼容提示译为中文，保留原配置字段和保存风险提醒。
- 修复无效服务器范围导入时的异常处理，保留输入与错误提示。
- 为 3.22 x86 补齐默认 RDCore 引擎所需的本地依赖。

## 开始使用

1. 下载并完整解压 [Release 源码包](https://github.com/kaixinit/RDCMan-Chinese-Patches/releases/latest)。
2. 准备有权使用的对应原版，核对 SHA256。
3. 按[使用指南](docs/USAGE.md)选择模块，预览、生成并复检中文副本。

以下以 2.93 为例，在仓库根目录打开 PowerShell。输入原版的完整路径时无需加引号；输出位置为桌面的新文件夹。

```powershell
Set-Location .\patches\rdcman-2.93
$source = Read-Host '原版 RDCMan.exe 的完整路径'
$output = Join-Path ([Environment]::GetFolderPath('Desktop')) 'RDCMan-2.93-zh'

.\Apply-RdcManPatch.ps1 -SourcePath $source -OutputDirectory $output -WhatIf
.\Apply-RdcManPatch.ps1 -SourcePath $source -OutputDirectory $output -DownloadDependency
.\Test-RdcManPatch.ps1 -OutputDirectory $output
```

输出目录必须尚不存在。`-DownloadDependency` 用于获取固定构建依赖，不下载 RDCMan。原版输入不会被覆盖；完成后手动打开输出目录中的程序。

## 使用须知

- 离线构建、Python 路径、恢复英文副本及常见问题见[使用指南](docs/USAGE.md)。
- 连接文件和个人设置应自行备份；汉化不消除新旧版本之间的配置兼容限制。
- 系统或远端返回的消息可能仍为原语言。验证范围见[验证说明](docs/VALIDATION.md)。
- 版权、依赖和许可范围见 [NOTICE.md](NOTICE.md)、[LICENSE.md](LICENSE.md) 和[第三方说明](THIRD_PARTY_NOTICES.md)。

如需修改翻译或重新生成源码包，请阅读[维护指南](docs/MAINTENANCE.md)。反馈问题时请注明模块、补丁版本和复现步骤，不附真实连接配置或凭据。
