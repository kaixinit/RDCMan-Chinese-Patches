# 第三方来源与依赖

本源码包不附带下列产品、安装包或运行库二进制。

| 项目 | 用途 | 来源与许可 |
|---|---|---|
| Microsoft RDCMan / Sysinternals | 使用者自行取得的原版输入 | [官方页面](https://learn.microsoft.com/en-us/sysinternals/downloads/rdcman)、[许可条款](https://learn.microsoft.com/en-us/sysinternals/license-terms) |
| Mono.Cecil 0.11.6 | 读取、修改和复核托管程序集 | [NuGet 固定版本](https://www.nuget.org/packages/Mono.Cecil/0.11.6)、[上游许可](https://github.com/jbevain/cecil/blob/0.11.6/LICENSE.txt)，上游包标注 MIT |
| Python 3.9+ | 3.22 单文件包处理及 x86 依赖提取，仅使用标准库 | [Python 官网](https://www.python.org/)、[许可说明](https://docs.python.org/3/license.html) |
| Microsoft VC++ Runtime 14.51.36247.0 x86 | 满足 3.22 x86 默认 RDCore 的原生依赖 | [微软官方说明](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist)，精确包地址及哈希见 x86 的 `patch.json` |
| Windows / .NET Framework | PowerShell 和 2.93 本地运行检查 | 使用者设备上的系统组件，适用其原有许可 |

Mono.Cecil 的包和目标框架 DLL 均校验固定 SHA256；不从未知镜像获取。Windows PowerShell 5.1 使用 net40 DLL，PowerShell 7 使用 netstandard2.0 DLL。

x86 的微软运行库包校验固定哈希和微软签名，仅提取七项固定 DLL，不运行安装器。提取的 DLL 会参与本地成品构建，但不进入本仓库或源码 ZIP，其权利不因补丁而改变。

各模块的 `docs/依赖说明.md` 和 `patch.json` 提供完整校验值和离线准备方法。仓库中的下载脚本不构成对依赖内容的重新许可。
