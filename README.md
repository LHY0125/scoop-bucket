# LHY0125 Scoop Bucket

Personal [Scoop](https://scoop.sh) bucket for LHY0125 projects, plus selected third-party tools.

## Usage

```powershell
scoop bucket add lhy https://github.com/LHY0125/scoop-bucket
scoop install lhy/patheditor-gui    # 图形界面
scoop install lhy/patheditor-cli    # 命令行
scoop install lhy/aoci-code         # AOCI 认知索引 MCP 服务端
scoop install lhy/agency-agents-app # 智能体人设浏览器（桌面应用）
```

## Manifests


| App                 | Description                                                         |
| --------------------- | --------------------------------------------------------------------- |
| `patheditor-gui`    | Graphical editor for the Windows PATH and environment variables     |
| `patheditor-cli`    | Command-line editor for the Windows PATH environment variable       |
| `aoci-code`         | MCP server and CLI that keeps a versioned codebase index for agents |
| `agency-agents-app` | Desktop app for browsing and installing the agency-agents roster    |

`patheditor-gui` 为免安装版（portable zip 解压即用，不写注册表、不注册卸载项）。`patheditor-cli` 为单文件 CLI。

`aoci-code` 是第三方项目 [aoci-spec/aoci-code](https://github.com/aoci-spec/aoci-code)，非本仓库作者所有。它同时提供 `aoci` 命令行和一个 stdio MCP 服务端（`aoci mcp`）。

`agency-agents-app` 是第三方项目 [msitarzewski/agency-agents-app](https://github.com/msitarzewski/agency-agents-app)，
非本仓库作者所有。上游只发布 NSIS 安装器（无便携 zip），本清单用 `pre_install` 调 7-Zip 解包为免安装形态，
不写注册表、不注册卸载项。它需要 Microsoft Edge WebView2 运行时（当前 Windows 10/11 已预装）。

> 注意：`extras` bucket 中另有一个无关项目占用了 `patheditor` 这个名字，请勿安装 `extras/patheditor`。

## Links

- [PathEditor](https://github.com/LHY0125/PathEditor)
- [AOCI-CODE](https://github.com/aoci-spec/aoci-code)
- [Agency Agents](https://github.com/msitarzewski/agency-agents-app)（应用本体 / [官网](https://agencyagents.app)）
- [agency-agents](https://github.com/msitarzewski/agency-agents)（人设内容仓库）
- [Bucket Issues](https://github.com/LHY0125/scoop-bucket/issues)

## License

本仓库的清单与文档以 MIT 授权。各软件包遵循其各自许可证：`patheditor-*` 为 MIT，`aoci-code` 为 FSL-1.1-MIT，`agency-agents-app` 为 MIT。
