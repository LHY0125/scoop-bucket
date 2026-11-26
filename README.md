# LHY0125 Scoop Bucket

个人 [Scoop](https://scoop.sh) bucket（桶名 `lhy`）：收录自有项目，以及少量日常使用的第三方工具。

## 快速开始

```powershell
scoop bucket add lhy https://github.com/LHY0125/scoop-bucket
scoop install lhy/<app>    # <app> 取下方清单中的名字
```

## 应用清单

### 自有项目

| App | 说明 |
| --- | --- |
| `patheditor-gui` | Windows PATH 与环境变量图形编辑器 |
| `patheditor-cli` | Windows PATH 命令行编辑器；命令为 `patheditor`，并提供 `path` 别名 |
| `nascli` | 绿联 NAS OpenCLI 客户端，走 UGOS Pro 的访问令牌接口 |

### 第三方工具

| App | 上游 | 说明 |
| --- | --- | --- |
| `ugos-cli` | [metaneutrons/ugos-cli](https://github.com/metaneutrons/ugos-cli) | 绿联 NAS 管理 CLI、MCP 服务端与 Rust 客户端库 |
| `unc` | [UGOS Pro 开发者门户](https://developer.ugnas.com/) | 绿联官方 CLI：文件、Docker、存储、应用检索与控制面板 |
| `aoci-code` | [aoci-spec/aoci-code](https://github.com/aoci-spec/aoci-code) | 本地代码库与数据库模式的版本化索引，提供 `aoci` CLI 与 stdio MCP 服务端 |
| `agency-agents-app` | [应用本体](https://github.com/msitarzewski/agency-agents-app) / [官网](https://agencyagents.app) | 浏览、安装与跟踪 agency-agents 人设的桌面应用 |
| `termix-cli` | [Termix-SSH/CLI](https://github.com/Termix-SSH/CLI) | Termix 服务端命令行客户端：SSH 终端、远程执行、SFTP、隧道、Docker |
| `rust-anything` | [erkamyaman/rust-anything](https://github.com/erkamyaman/rust-anything) | 把应用逐块改写成 Rust，并用原实现的行为记录校验每一步 |
| `rscoop` | [AmarBego/Rscoop](https://github.com/AmarBego/Rscoop) | Scoop 包管理器图形界面：搜索、安装、更新、清理 |
| `contextmenumgrplus` | [PLFJY/ContextMenuMgr](https://github.com/PLFJY/ContextMenuMgr) | Windows 右键菜单管理，拦截第三方应用塞入的条目 |

## 绿联 NAS：三个包怎么选

`nascli`、`ugos-cli`、`unc` 互不依赖，功能有重叠，按用途选择：

- `nascli` —— 自研，走 OpenCLI 访问令牌接口，覆盖文件、Docker、下载、存储、应用等。
- `ugos-cli` —— 第三方，同时提供 CLI、MCP 服务端与 Rust 客户端库。
- `unc` —— 绿联官方，功能收敛在文件、Docker、存储、应用检索与控制面板。

## 安装形态

| App | 形态 |
| --- | --- |
| `patheditor-gui` | portable zip，解压即用，不写注册表、不注册卸载项 |
| `patheditor-cli`、`nascli`、`termix-cli` | 单文件可执行 |
| `ugos-cli` | zip，解压后为 `ugos-cli.exe` 与 `ugos-mcp.exe` |
| `unc` | zip，包内带版本目录 |
| `aoci-code` | zip，内含 `aoci.exe` |
| `agency-agents-app` | 上游只发 NSIS 安装器；清单用 `pre_install` 调 7-Zip 解包为免安装形态，需要 Microsoft Edge WebView2 运行时（当前 Windows 10/11 已预装） |
| `rust-anything` | zip，包内含版本目录、README 与 CHANGELOG |
| `rscoop` | 单文件可执行（Tauri，需要 Microsoft Edge WebView2 运行时；当前 Windows 10/11 已预装） |
| `contextmenumgrplus` | self-contained portable zip（x64 / x86 / arm64）；部分操作会安装或修复 Windows 服务 |

## 使用提示

- `termix-cli`：单文件二进制（Node SEA，不需要 Node.js），要求 Termix 2.9 及以上，且服务端已启用对应插件；认证优先读 `TERMIX_URL` / `TERMIX_API_KEY` 等环境变量，配置落在 `%APPDATA%\termix`。
- `aoci-code`：`aoci` 与 `aoci mcp` 是同一个二进制；MCP 宿主建议指向版本稳定的 shim（`%SCOOP%\shims\aoci.exe`），`aoci init` 写入配置后需重启宿主。
- `agency-agents-app`：安装器尚未代码签名，首次运行可能触发 SmartScreen；人设会写入它检测到的工具配置目录（如 `~/.claude/agents`），人设内容在 [agency-agents](https://github.com/msitarzewski/agency-agents) 仓库。
- `rust-anything`：上游 Windows 仅发布 x86_64 构建；安装后运行 `rust-anything setup` 才会把 MCP 服务端与工作流技能注册给 Claude Code、Codex、Cursor、Gemini CLI、OpenCode（`setup --remove` 可撤销，改动前生成 `<file>.rust-anything.bak`）。
- `rscoop`：应用内自带更新器可能覆盖 Scoop 管理的二进制；优先用 `scoop update rscoop` 更新，保证 Scoop 记录的版本与实际一致。
- `contextmenumgrplus`：与作者的 beta 包 `contextmenumgrplus-beta` 互斥，不能并排安装；`Data` 目录走 Scoop 持久化。

## 注意事项

- `extras` bucket 中另有一个无关项目占用了 `patheditor` 这个名字，请勿安装 `extras/patheditor`。
- `ContextMenuMgr` 这个名字在 `anderlli0053/DEV-tools` 等桶里指另一个 Freeware 工具（tomato-extra）；本桶的 `contextmenumgrplus` 才是 PLFJY 的 Context Menu Manager Plus。

## 相关链接

- [PathEditor](https://github.com/LHY0125/PathEditor)（`patheditor-*` 上游）
- [ugreen-nas-cli](https://github.com/LHY0125/ugreen-nas-cli)（`nascli` 上游）
- [Bucket Issues](https://github.com/LHY0125/scoop-bucket/issues)

## 维护

清单编写、校验与发布流程见 [AGENTS.md](AGENTS.md) 与 [.claude/skills/scoop-bucket/SKILL.md](.claude/skills/scoop-bucket/SKILL.md)。

## License

本仓库的清单与文档以 MIT 授权。各软件遵循自身许可证：`patheditor-*` 与 `nascli` 为 MIT，`ugos-cli` 为 GPL-3.0-or-later，`unc` 为专有许可，`aoci-code` 为 FSL-1.1-MIT，`agency-agents-app` 为 MIT，`termix-cli` 为 Apache-2.0，`rust-anything` 为 MIT，`rscoop` 为 MIT，`contextmenumgrplus` 为 GPL-3.0-only。
