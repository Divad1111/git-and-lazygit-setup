# Git / Beyond Compare / lazygit 一键配置

适用于 Windows、macOS、Linux。运行时完全使用 Shell，不依赖 Python、pip、PyYAML、jq 或 yq。

## 1. 当前 lazygit 的 e 为什么没有调用 BCompare

lazygit 0.66.1 的文件面板中，内置 `e` 调用编辑器，不调用 Git 合并工具。你的原配置只把外部合并绑定到了 Ctrl+B 和 Ctrl+M。因此，Git 已设置 `merge.tool=bc` 并不代表 lazygit 的 e 会自动调用它。

本包配置三个文件面板按键：

- `e`：选中文件在 Git 暂存区存在冲突项时，运行 `git mergetool --tool=bc --no-prompt -- 文件`；没有冲突时，仍使用 `core.editor` 指定的编辑器。
- `Ctrl+B`：用 BCompare 处理选中的冲突文件。
- `F7`：用 BCompare 依次处理所有冲突文件。

旧的 Ctrl+M 合并绑定迁移到 F7，避免一些终端把 Ctrl+M 和回车识别成同一个按键。这里修改的是文件面板的自定义命令，不改变其他面板的 e。

关闭并重新启动 lazygit 后生效。保存并关闭合并窗口后检查 `git status`，再继续 merge/rebase/cherry-pick。三方合并需要 Beyond Compare Pro 授权；脚本检测安装路径，不检测许可证。

## 2. 运行方式

先把整个文件夹复制/解压到新电脑。不要只复制某个入口文件，公共脚本和配置模板也需要一起保留。

Windows PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1 --check
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1

# 手动指定 BCompare 和临时目录
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1 --bc-path "C:\Program Files (x86)\Beyond Compare\BCompare.exe" --temp-root "D:\GitTemp"
```

Windows Git Bash：

```bash
sh setup-windows.sh --check
sh setup-windows.sh
```

macOS：

```bash
sh setup-macos.sh --check
sh setup-macos.sh
```

Linux：

```bash
sh setup-linux.sh --check
sh setup-linux.sh
```

不需要使用 sudo 执行配置脚本。它修改当前用户的配置，不修改项目文件。

Windows PowerShell 入口使用 Git for Windows 自带的 Bash，不需要 WSL。macOS 使用系统自带的 Bash 3.2，Linux 使用 Bash。

## 3. 缺少工具时

脚本检查 Git 2.28+、lazygit、Beyond Compare，以及 awk、sed、mktemp 等系统基础工具。Windows 的基础工具随 Git for Windows 提供，macOS 通常由系统提供，Linux 可用发行版包管理器安装。

缺少依赖时输出安装提示并以退出码 2 结束，安装依赖后重新执行即可。脚本不会自动下载安装程序。

Windows 常用安装命令：

```powershell
winget install --id Git.Git -e
winget install --id JesseDuffield.lazygit -e
```

Beyond Compare 请从官网安装；自定义路径用 `--bc-path` 传入。

macOS 可使用：

```bash
brew install git lazygit
brew install --cask beyond-compare
```

在 Beyond Compare 菜单中执行 Install Command Line Tools，确保可以找到 bcomp。Linux 使用适合发行版的 Git、lazygit 软件包和官方 Beyond Compare .deb/.rpm。

## 4. 配置范围和跨系统适配

`profile.conf` 是本次导出的便携设置，内容不是 Shell 代码，按 `配置项=值` 逐行读取，可以修改其中的默认身份信息。

迁移内容包括常用 Git 别名、默认分支、fetch 清理、pull 仅快进、histogram diff、diff3 冲突显示、rerere、行尾策略、BCompare Diff/Merge，以及 lazygit 快捷键。

新电脑会重新检测 Bash、BCompare 和编辑器的位置，不直接使用旧电脑的绝对路径。已有姓名、邮箱、编辑器和凭证助手默认保留；身份为空时才使用 profile.conf 中的姓名、邮箱。可显式传入 `--name`、`--email`、`--editor` 覆盖。

Windows 增加 `core.longpaths=true`。凭证助手在 Windows 检测 manager/manager-core，macOS 检测 osxkeychain，已有配置则保留；Linux 不强行设置某种凭证存储方式。

`git graph` / `git fh 文件` 在 Windows 安装 TortoiseGit 时继续调用它；其他情况下显示 Git 终端历史。TortoiseGit 不属于必需依赖。

你的原配置含 `safe.directory=*`，便携配置也包含该值。如不希望在新电脑导入它，请加 `--no-trust-all`。该选项只控制导入，不删除电脑上原有的 safe.directory 设置。

原始 Windows 配置保存在 `snapshot/` 中，仅作为备查。快照可能包含旧的 Python 别名路径；安装时不执行这些快照，实际安装的是新的 Shell 版本。

## 5. 增强版 git rv

```bash
git rv
git rv --staged
git rv HEAD
git rv master feature/login
git rv origin/master...HEAD -- UnityProject/Assets/LuaScripts/

git rv --author='张三'
git rv --grep='SG-12345'
git rv --author='张三' --grep='SG-12345'
git rv --author='张三' --since='2 weeks ago'
git rv --grep='SG-12345' -- UnityProject/Assets/LuaScripts/
```

筛选模式默认搜索当前分支可达的提交历史，所有命中提交放到一个 BCompare 目录窗口中，每次提交建立子目录，左侧是提交前，右侧是提交后。首次提交与空目录比较，合并提交与第一个父提交比较，重命名显示为旧路径删除和新路径新增。

筛选窗口只读，不修改工作区或暂存区。关闭窗口后清理本次临时目录。不会为了聚合审核而切换分支、cherry-pick 或重写历史。文件内容来自 Git 对象，LFS 文件显示仓库中的指针内容。

`--grep` 使用 Git 正则语义，是包含匹配。需要严格匹配单号时：

```bash
git rv -E --grep='(^|[^[:alnum:]_-])SG-12345([^[:alnum:]_-]|$)'
```

## 6. 临时目录

普通和筛选 rv 共用 `rv.tempRoot`。已有配置保留；新电脑没配置时使用用户目录里的 `.git-rv/temp`。

```bash
git config --global rv.tempRoot 'D:/GitTemp'
git config --global --get rv.tempRoot
git config --global --unset rv.tempRoot
```

也可以在安装时传 `--temp-root`。旧电脑的 D 盘路径不会自动复制到没有 D 盘的新电脑。

## 7. 重入、备份和回滚

- 安装前先检查工具和配置结构，`--check` 不写入配置。
- Git 配置先在同目录的临时文件中准备，通过 Git 自身解析验证后再替换。
- lazygit 保留其他设置和不相关的自定义命令，只替换本包管理的文件面板按键。
- 写入前保存原文件；有实际变化才备份，字节相同的文件不重写，不增加重复快捷键。
- 写入失败时，恢复本次已经替换的文件。
- 备份位于安装目录的 `backups/时间-进程号/`，其中 `manifest.tsv` 记录目标文件、原文件是否存在和对应备份路径。
- 第二次在相同电脑上、使用相同参数运行，应显示 `Already configured`。

默认辅助脚本目录是 `~/.local/share/git-cli-kit`，可用 `--install-dir` 修改；随后执行会优先使用已记录的 `gitkit.installDir`。

```bash
sh setup-linux.sh --help
sh setup-windows.sh --lazygit-only
```

`--lazygit-only` 用于只修复 e/外部合并入口，保留现有 rv 和其他 Git 偏好。完整迁移、摆脱历史 Python 版 rv 请使用普通安装模式。

## 8. YAML 支持范围

为避免引入 YAML 运行时依赖，安装器使用系统 awk 对标准的缩进块式 YAML 做定点更新，保留无关文本和注释。你当前的 lazygit 配置以及 lazygit 常见的块式配置都属于这种格式。

顶层 `customCommands` 必须是块式列表；整个配置使用 JSON/流式 YAML，或某个会冲突的自定义命令使用多按键列表时，脚本会明确拒绝修改，提示改成块式、单按键形式后重试，不会猜测或覆盖原配置。YAML 文件应使用空格缩进，不使用 Tab。

## 9. 依据与验证范围

- [lazygit 0.66.1 的编辑器设置](https://github.com/jesseduffield/lazygit/blob/v0.66.1/docs/Config.md#configuring-file-editing)
- [自定义命令与按键覆盖规则](https://github.com/jesseduffield/lazygit/blob/v0.66.1/docs/Custom_Command_Keybindings.md)
- [Beyond Compare Git 配置](https://www.scootersoftware.com/kb/vcs)
- [Beyond Compare macOS Git 配置](https://www.scootersoftware.com/kb/vcs_osx)

本次环境是 Windows，已通过 6 组隔离测试，覆盖重复安装不改写、缺依赖或不支持的 YAML 时不写配置、身份与临时目录保留、真实 Git 冲突文件分流、Windows 两种入口传参，以及按作者/单号导出首次提交、二进制、中文路径、删除和重命名的审核目录。测试使用模拟合并工具验证 Git 调用，不代替 BCompare 许可证和图形操作验证。

已将本机配置迁移到 Shell 版本，并再次执行安装，确认显示 `Already configured`；真实 lazygit 0.66.1 已成功加载新配置。macOS/Linux 入口已做 Shell 语法与兼容写法检查，未在真实 macOS/Linux 桌面环境执行 BCompare 图形合并。
