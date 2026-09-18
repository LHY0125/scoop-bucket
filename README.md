# LHY0125 Scoop Bucket

Personal [Scoop](https://scoop.sh) bucket for LHY0125 projects.

## Usage

```powershell
scoop bucket add lhy https://github.com/LHY0125/scoop-bucket
scoop install lhy/patheditor        # GUI
scoop install lhy/patheditor-cli    # 命令行
```

## Manifests

| App               | Description                                                     |
| ----------------- | --------------------------------------------------------------- |
| `patheditor`      | Graphical editor for the Windows PATH and environment variables |
| `patheditor-cli`  | Command-line editor for the Windows PATH environment variable   |

`patheditor` 为 GUI 版，从 NSIS 安装包解包提取，不做真实安装（不写注册表、不注册卸载项）。`patheditor-cli` 为单文件 CLI。

## Links

- [PathEditor](https://github.com/LHY0125/PathEditor)
- [Bucket Issues](https://github.com/LHY0125/scoop-bucket/issues)

## License

MIT
