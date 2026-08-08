# ClipTiny

轻量、原生的 macOS 剪贴板历史工具。支持文本与图片、搜索、预览和自动粘贴，
可保留 50、100、200 或 500 条记录。

## 使用

| 快捷键 | 功能 |
| --- | --- |
| `⌘⇧V` | 打开或关闭历史窗口 |
| `↑` / `↓` | 选择记录 |
| `Enter` | 粘贴所选记录 |
| `⌘F` | 搜索 |
| `⌘W` / `Esc` | 关闭窗口 |

自动粘贴需要“辅助功能”权限；未授权时仍会复制到系统剪贴板。保留条目数可在
菜单栏中设置。

## 安装

从 [Releases](https://github.com/richie-king/SimpleClip/releases/latest) 下载通用安装包
（macOS 13+）。首次运行请在 Finder 中右键 ClipTiny，选择“打开”。

从源码构建：

```sh
./scripts/build-app.sh
```

## 隐私

无网络请求和遥测。历史使用 AES-GCM 加密并仅保存在本机，密钥由 macOS 钥匙串
管理；系统标记为临时、保密或自动生成的内容不会被记录。

开发与维护说明见 [MAINTENANCE.md](MAINTENANCE.md)；项目采用 [MIT License](LICENSE)。
