# 上传 GitHub 与发布源码包

项目仓库：[kaixinit/RDCMan-Chinese-Patches](https://github.com/kaixinit/RDCMan-Chinese-Patches)。已有仓库维护时，可先执行 `git clone https://github.com/kaixinit/RDCMan-Chinese-Patches.git`，再按本文的校验和打包步骤操作。

本说明仅处理本地源码项目的上传步骤，不创建仓库、不登录账号，也不会代为上传。

## 仓库根目录

将含有根 `README.md`、`repository.json`、`patches/` 和 `tools/` 的这个文件夹作为仓库根目录。不要上传上一级目录，那里可能放有成品或工作文件。

推荐仓库名：`RDCMan-Chinese-Patches`。简介可以使用：

> RDCMan 2.93 与 3.22 x64/x86 中文补丁、构建和复检脚本。仅源码资料，不提供原版或汉化成品二进制。

## 上传前校验

在仓库根目录执行：

```powershell
.\tools\Test-Source.ps1
```

该工具核对源文件清单、三个模块的内部清单、文件类型和用户路径。仓库中的依赖缓存或 Git 元数据不进入打包；未知文件会被提示处理。`.gitignore` 是防误提交措施，打包仍使用独立的显式白名单。

## 使用 Git 推送

先在 GitHub 创建一个空仓库；根 README 和版权文件已随本项目提供，不要在创建页面额外生成不同的 README 或许可证。下面使用本项目实际仓库地址；首次上传到其他账号时，请替换为该账号新建仓库的地址。

```powershell
git init
git branch -M main
git status --short
git add .
git diff --cached --stat
git commit -m "Add RDCMan Chinese patch scripts and documentation"
git remote add origin https://github.com/kaixinit/RDCMan-Chinese-Patches.git
git push -u origin main
```

认证由使用者自己完成。项目不存储访问令牌、登录凭据或签名密钥。推送前检查暂存文件列表；应只有本仓库的文本源码与说明。

根 `.gitattributes` 禁止自动换行转换，以保留模块清单所需的精确文件字节和 PowerShell BOM。克隆后再次运行 `tools/Test-Source.ps1` 即可复核。

## 维护和重新打包

修改译表或代码后，应进行相应验证。更新清单和生成源码 ZIP：

```powershell
.\tools\Update-SourceManifest.ps1
.\tools\Test-Source.ps1
.\Package-Source.ps1 -DestinationZip 'D:\Exports\RDCMan-Chinese-Patches-source.zip'
```

ZIP 目标必须位于仓库外。更新清单会记录当前允许文件的字节，不能代替代码审查或数字签名；不要用它掩盖不明来源的修改。

GitHub Release 只附上由根打包脚本生成的源码 ZIP。不要附上本地生成的 EXE、原版备份、DLL、VC++ 安装包、`.local` 缓存、连接配置或工作目录。

本仓库没有新增覆盖全部内容的 MIT/GPL 许可证；请保留 `NOTICE.md`、`LICENSE.md` 及第三方来源说明，不要把微软内容标为自有开源代码。
