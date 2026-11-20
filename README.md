# LHY0125 Scoop Bucket

Personal [Scoop](https://scoop.sh) bucket for LHY0125 projects, plus selected third-party tools.

## Usage

```powershell
scoop bucket add lhy https://github.com/LHY0125/scoop-bucket
scoop install lhy/patheditor-gui    # PATH / 环境变量图形编辑器
scoop install lhy/patheditor-cli    # PATH 命令行编辑器
scoop install lhy/nascli            # 绿联 NAS OpenCLI 客户端（自研）
scoop install lhy/ugos-cli          # 绿联 NAS 管理 CLI + MCP 服务端
scoop install lhy/unc               # 绿联官方 NAS CLI
scoop install lhy/aoci-code         # AOCI 认知索引 MCP 服务端
scoop install lhy/agency-agents-app # 智能体人设浏览器（桌面应用）
scoop install lhy/termix-cli        # Termix 服务端命令行客户端
scoop install lhy/rust-anything     # 逐块改写为 Rust 并用原行为记录校验
```

## Manifests


| App                 | Description                                                         |
| --------------------- | --------------------------------------------------------------------- |
| `patheditor-gui`    | Graphical editor for the Windows PATH and environment variables     |
| `patheditor-cli`    | Command-line editor for the Windows PATH environment variable       |
| `nascli`            | CLI for the UGOS Pro OpenCLI access-token API                       |
| `ugos-cli`          | CLI, MCP server and Rust client library for UGREEN NAS (UGOS)       |
| `unc`               | Official UGREEN NAS CLI: files, Docker, storage, apps, search       |
| `aoci-code`         | MCP server and CLI that keeps a versioned codebase index for agents |
| `agency-agents-app` | Desktop app for browsing and installing the agency-agents roster    |
| `termix-cli`        | Command-line client for Termix servers (SSH, SFTP, tunnels, Docker) |
| `rust-anything`     | Rewrites an app in Rust piece by piece, verified against recorded behavior |

安装形态：`patheditor-gui` 为 portable zip（解压即用，不写注册表、不注册卸载项）；`patheditor-cli`、`nascli`、`unc`、`termix-cli` 为单文件可执行；`rust-anything` 为 zip（内含版本目录、README 与 CHANGELOG）；`agency-agents-app` 上游只发 NSIS 安装器，本清单用 `pre_install` 调 7-Zip 解包成免安装形态，需要 Microsoft Edge WebView2 运行时（当前 Windows 10/11 已预装）。

### 绿联 NAS 相关

三个包互不依赖、功能有重叠，按用途选：

- `nascli` —— 自研项目 [LHY0125/ugreen-nas-cli](https://github.com/LHY0125/ugreen-nas-cli)，走 UGOS Pro 的 OpenCLI 访问令牌接口（文件、Docker、下载、存储、应用等）。
- `ugos-cli` —— 第三方 [metaneutrons/ugos-cli](https://github.com/metaneutrons/ugos-cli)，同时提供 CLI、MCP 服务端与 Rust 客户端库。
- `unc` —— 绿联官方 [UGOS Pro 开发者门户](https://developer.ugnas.com/) 发布的 CLI，功能收敛在文件、Docker、存储、应用检索与控制面板。

### 第三方包

以下不是本仓库作者的项目，清单只做分发适配：

- `aoci-code` —— [aoci-spec/aoci-code](https://github.com/aoci-spec/aoci-code)，提供 `aoci` 命令行与 stdio MCP 服务端（`aoci mcp`）。
- `agency-agents-app` —— [msitarzewski/agency-agents-app](https://github.com/msitarzewski/agency-agents-app)，人设内容在同组织的 [agency-agents](https://github.com/msitarzewski/agency-agents) 仓库。
- `termix-cli` —— [Termix-SSH/CLI](https://github.com/Termix-SSH/CLI)，单文件二进制（自带运行时，不需要 Node.js），配合 Termix 2.9 及以上服务端；认证读 `TERMIX_URL` / `TERMIX_API_KEY`，配置落在 `%APPDATA%\termix`。
- `rust-anything` —— [erkamyaman/rust-anything](https://github.com/erkamyaman/rust-anything)，录制原项目行为后逐块改写成 Rust；上游 Windows 仅发布 x86_64 构建。安装后运行 `rust-anything setup` 才会把 MCP 服务端与工作流技能注册给 Claude Code、Codex、Cursor、Gemini CLI、OpenCode（`setup --remove` 可撤销，改动前会生成 `<file>.rust-anything.bak`）。

> 注意：`extras` bucket 中另有一个无关项目占用了 `patheditor` 这个名字，请勿安装 `extras/patheditor`。

## Links

- [PathEditor](https://github.com/LHY0125/PathEditor)
- [ugreen-nas-cli](https://github.com/LHY0125/ugreen-nas-cli)
- [ugos-cli](https://github.com/metaneutrons/ugos-cli)
- [UGOS Pro Developer](https://developer.ugnas.com/)
- [AOCI-CODE](https://github.com/aoci-spec/aoci-code)
- [Agency Agents](https://github.com/msitarzewski/agency-agents-app)（应用本体 / [官网](https://agencyagents.app)）
- [agency-agents](https://github.com/msitarzewski/agency-agents)（人设内容仓库）
- [Termix CLI](https://github.com/Termix-SSH/CLI)
- [rust-anything](https://github.com/erkamyaman/rust-anything)
- [Bucket Issues](https://github.com/LHY0125/scoop-bucket/issues)

## License

本仓库的清单与文档以 MIT 授权。各软件包遵循其各自许可证：`patheditor-*` 与 `nascli` 为 MIT，`ugos-cli` 为 GPL-3.0-or-later，`unc` 为专有许可，`aoci-code` 为 FSL-1.1-MIT，`agency-agents-app` 为 MIT，`termix-cli` 为 Apache-2.0，`rust-anything` 为 MIT。
