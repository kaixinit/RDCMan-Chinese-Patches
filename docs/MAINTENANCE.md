# 维护指南

本文面向修改翻译或维护补丁的贡献者。安装和日常使用请参阅[使用指南](USAGE.md)。

## 修改翻译

各模块相互独立，以自身的 `patch.json` 和 `patches/translations.json` 为准。修改已有译文时只调整 `Chinese`，保留原文、定位信息、格式占位符和必要的快捷键。

新增条目需确认原文用于界面显示，同步翻译数量和 `docs/中英对照.tsv`。XML 节点、配置键、枚举值、凭据内部标识和用户自定义名称不作显示文本替换。

布局及动态文字的处理集中在 `scripts/Apply-Ui.ps1`，修改时需保留原缩放机制和限定方法检查。具体文件职责见各模块的维护说明。

## 验证修改

在仓库根目录更新清单并检查完整性：

```powershell
.\tools\Update-SourceManifest.ps1
.\tools\Test-Source.ps1
```

清单记录源文件字节，不代替代码审查或数字签名。PowerShell 文件保留 UTF-8 BOM；`.gitattributes` 用于避免 Git 自动转换换行。

随后使用支持的原版在仓库外重新构建和复检。涉及提示、布局或错误处理的修改，还应检查对应界面和错误状态。完整流程测试入口为各模块的 `tests/Test-Workflow.ps1`。

## 生成源码包

在仓库根目录执行以下命令。输出 ZIP 位于桌面，文件已存在时须更换名称。

```powershell
$zip = Join-Path ([Environment]::GetFolderPath('Desktop')) 'RDCMan-Chinese-Patches-source.zip'
.\Package-Source.ps1 -DestinationZip $zip
```

打包只收集允许清单中的文本文件。不要将程序、依赖、原版备份、连接配置或工作目录作为发布附件。

提交修改时请说明影响的模块、变更目的和验证范围；版权及引用范围遵循 [NOTICE.md](../NOTICE.md) 与 [LICENSE.md](../LICENSE.md)。
