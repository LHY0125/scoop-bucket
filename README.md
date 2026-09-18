# LHY0125 Scoop Bucket

Personal [Scoop](https://scoop.sh) bucket for LHY0125 projects.

## Usage

```powershell
scoop bucket add lhy https://github.com/LHY0125/scoop-bucket
scoop install lhy/patheditor-gui    # 图形界面
scoop install lhy/patheditor-cli    # 命令行
```

## Manifests

| App                | Description                                                     |
| ------------------ | --------------------------------------------------------------- |
| `patheditor-gui`   | Graphical editor for the Windows PATH and environment variables |
| `patheditor-cli`   | Command-line editor for the Windows PATH environment variable   |

`patheditor-gui` 为免安装版（portable zip 解压即用，不写注册表、不注册卸载项）。`patheditor-cli` 为单文件 CLI。

> 注意：`extras` bucket 中另有一个无关项目占用了 `patheditor` 这个名字，请勿安装 `extras/patheditor`。

## Links

- [PathEditor](https://github.com/LHY0125/PathEditor)
- [Bucket Issues](https://github.com/LHY0125/scoop-bucket/issues)

## License

MIT
