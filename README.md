# RDCMan 中文补丁与脚本

[项目主页](https://github.com/kaixinit/RDCMan-Chinese-Patches) · [仅源码 Release](https://github.com/kaixinit/RDCMan-Chinese-Patches/releases/latest)

为指定版本的 RDCMan 在本地生成中文副本，提供翻译数据、构建脚本、复检和恢复工具。汉化作者：**kaixinit**。

本仓库不包含 RDCMan 原版、汉化 EXE、DLL、安装包、依赖二进制或个人连接配置；不下载 RDCMan，也不代表 Microsoft 或 Sysinternals 官方项目。版权范围见 [NOTICE.md](NOTICE.md) 和 [LICENSE.md](LICENSE.md)。

## 支持版本

| 原版 | 补丁版本 | 补丁目录 | 构建所需环境 |
|---|---|---|---|
| 2.93.1431.0 | 0.1.5 | [rdcman-2.93](patches/rdcman-2.93/README.md) | Windows、PowerShell 5.1/7、.NET Framework 4.8 |
| 3.22.0.0 x64 | 0.1.3 | [rdcman-3.22-x64](patches/rdcman-3.22-x64/README.md) | Windows、PowerShell 5.1/7、Python 3.9+ |
| 3.22.0.0 x86 | 0.1.4 | [rdcman-3.22-x86](patches/rdcman-3.22-x86/README.md) | 同上，另需指定版本的 x86 VC++ 依赖 |

补丁版本与软件版本分开编号。脚本同时校验原版 SHA256；版本号相同、文件哈希不同也会拒绝。原版哈希和已验证的输出哈希见 [版本与校验值](docs/VERSIONS.md)。

## 包含的调整

- 菜单、右键、内置分组、常用提示和部分动态选项的中文显示。
- 尺寸标签、分辨率按钮及关于窗口的排版调整。
- 启动配置兼容提示汉化，保留原 XML 路径、字段标识和保存风险说明。
- 修复无效服务器范围校验失败后误返回成功的问题，保留输入窗口及错误标记。
- 关于窗口署名统一为“汉化作者：kaixinit”，保留微软版权、原作者和官网链接。
- 3.22 x86 保留默认 RDCore 启动依赖修复；构建时从经校验的微软运行库包提取依赖，不执行安装器。

系统组件和远端返回的消息可能仍是原语言。未用真实账号进行远程连接测试，未逐档验证所有 DPI。

## 快速开始

先完整解压仓库，并自行取得有权使用的对应原版。官方产品页面：[Remote Desktop Connection Manager](https://learn.microsoft.com/en-us/sysinternals/downloads/rdcman)。官方页面可能只提供当前版本；本仓库不提供旧版本镜像。

打开 PowerShell，进入需要的补丁目录。以下以 2.93 为例；所有 `D:` 路径都是示例，须替换为自己的路径。**生成目录放在仓库外，且必须尚不存在。**

```powershell
Set-Location .\patches\rdcman-2.93

# 只校验和预览，不联网，也不生成程序
.\Apply-RdcManPatch.ps1 -SourcePath 'D:\RDCMan-original\2.93\RDCMan.exe' -OutputDirectory 'D:\RDCMan-build\2.93-zh' -WhatIf

# 从固定官方地址获取构建依赖，在本地生成副本
.\Apply-RdcManPatch.ps1 -SourcePath 'D:\RDCMan-original\2.93\RDCMan.exe' -OutputDirectory 'D:\RDCMan-build\2.93-zh' -DownloadDependency

# 复检刚生成的文件
.\Test-RdcManPatch.ps1 -OutputDirectory 'D:\RDCMan-build\2.93-zh'
```

3.22 x64 和 x86 的命令、Python 选择、离线构建、恢复步骤及常见问题，见 [完整使用步骤](docs/USAGE.md)。

构建不会覆盖输入原版、启动 RDCMan、连接服务器或代为接受许可。首次手动启动生成的副本时，程序使用原有汉化版的独立配置目录；目录标识见各版本说明。

## 仓库结构

```text
patches/
  rdcman-2.93/          2.93 补丁、译表、检查代码及说明
  rdcman-3.22-x64/      3.22 x64 补丁与单文件包工具
  rdcman-3.22-x86/      3.22 x86 补丁及运行库准备工具
docs/                  使用、版本、发布和验证说明
tools/                 合集源码校验与清单维护
Package-Source.ps1      只按清单生成源码 ZIP
source-manifest.json    合集文件字节清单
```

三个补丁独立运行，不会调用另一个版本的程序或构建目录。`patch.json` 中的原版和依赖哈希均为固定值。

## 上传 GitHub

直接将本文件夹作为仓库根目录；不要上传其上一级工作目录。具体步骤见 [GitHub 上传与源码发布](docs/GITHUB.md)。

上传前，在仓库根目录运行：

```powershell
.\tools\Test-Source.ps1
```

重新生成仅源码 ZIP：

```powershell
.\Package-Source.ps1 -DestinationZip 'D:\Exports\RDCMan-Chinese-Patches-source.zip'
```

打包采用显式文件清单，忽略本地依赖缓存，不把 Git 历史、原程序、构建结果或个人配置加入 ZIP。校验清单用于发现意外修改，不是数字签名。

验证记录见 [VALIDATION.md](docs/VALIDATION.md)。本项目以补丁资料形式整理，不自动取得微软软件的修改或再分发授权；详细边界见 [版权说明](NOTICE.md)。
