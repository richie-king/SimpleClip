# ClipTiny

轻量、原生的 macOS 剪贴板历史工具。支持文本与图片、搜索、预览和自动粘贴，
可保留 50、100、200 或 500 条记录。

## 使用

| 快捷键 | 功能 |
| --- | --- |
| `⌘⇧V` | 打开或关闭历史窗口 |
| `↑` / `↓` | 选择记录 |
| `Enter` | 粘贴所选记录 |
| `⌥Enter` | 纯文本格式清理粘贴（去除多余空行与首尾空白） |
| `⌘P` | 置顶 / 取消置顶当前记录（置顶项常驻最前且不被容量裁剪） |
| `⌘⌫` | 删除当前记录 |
| `⌘R` | 在访达中定位高亮文件记录 |
| `⌘O` | 在默认浏览器中打开链接 |
| `⌘C` | 复制选中记录并关闭窗口（不触发自动粘贴） |
| `⌘F` | 聚焦搜索框（支持多词 AND 搜索与中文拼音首字母匹配） |
| `⌘1` / `⌘2` / `⌘3` | 切换“全部”、“文本”、“图片”分类 |
| `⌘W` / `Esc` | 关闭窗口 |

自动粘贴需要“辅助功能”权限；未授权时仍会复制到系统剪贴板。保留条目数、窗口唤起位置（居中记忆/跟随鼠标/跟随输入光标）、排除应用名单与开机启动均可在菜单栏中便捷配置。支持常见 API Token / 敏感私钥智能脱敏保护及明文切换。

## 安装

从 [Releases](https://github.com/richie-king/SimpleClip/releases/latest) 下载通用安装包
（macOS 26+）。首次运行请在 Finder 中右键 ClipTiny，选择“打开”。

从源码构建：

需要带 macOS 26 或更新 SDK 的 Command Line Tools / Xcode。界面采用 AppKit，
使用随系统外观变化的原生液态玻璃，最低运行版本为 macOS 26。

```sh
./scripts/build-app.sh
```

## 自动化测试

在 macOS 26+、安装 macOS 26 或更新 SDK 的环境中运行：

```sh
./scripts/test.sh
```

GitHub Actions 在推送、拉取请求和手动触发时自动执行同一测试脚本。

使用 Swift Testing，覆盖历史去重、容量裁剪、加密持久化、图片处理和剪贴板采集。
测试使用临时目录、独立偏好设置及专用剪贴板，不读取真实历史或访问钥匙串。
可通过 `./scripts/test.sh --filter HistoryTests.testTextDeduplicationAndEmptyInput`
运行单个用例。

在已登录图形桌面的 Mac 上运行 UI 集成测试（会短暂打开测试窗口）：

```sh
CLIPTINY_UI_TESTS=1 ./scripts/test.sh --filter UITests
```

这 6 项测试使用真实 AppKit 控件、字段编辑器和窗口响应链，覆盖搜索、分类、
键盘选择、关闭、窗口尺寸恢复及浅深色下的最小尺寸布局。默认测试和 CI 跳过这些
需要图形会话的用例。它们不等同于系统级鼠标键盘端到端测试；全局快捷键、
跨应用粘贴、辅助功能权限和打包仍按维护手册手动验证。

### 桌面端到端与打包验证

```sh
./scripts/test-desktop.sh
./scripts/build-app.sh
./scripts/verify-app.sh
```

桌面测试需要真实图形会话及驱动的辅助功能/事件发送权限，会短暂接管键盘焦点。
它暂时退出已运行的 ClipTiny，启动使用隔离历史的同源测试应用及空白富文本接收器，
结束后恢复原应用与剪贴板。运行期间请勿操作键盘或复制内容。
测试应用没有辅助功能权限时，验证“只复制、由用户手动粘贴”的降级路径，并在
JSON 报告中明确跳过自动粘贴成功路径。报告位于 `work/desktop-tests/run.*/results.json`。
原应用的权限不会自动授予测试应用；如需补测授权路径，在系统设置中为
`work/desktop-tests/ClipTinyFixture.app` 授予辅助功能权限后重跑。

打包验证检查通用架构、最低系统版本、资源、菜单栏应用标记、签名与压缩解压完整性，
校验压缩包位于 `work/verification/ClipTiny-verified.zip`。

## 隐私

无网络请求和遥测。历史使用 AES-GCM 加密并仅保存在本机，密钥由 macOS 钥匙串
管理；系统标记为临时、保密或自动生成的内容不会被记录。

开发与维护说明见 [MAINTENANCE.md](MAINTENANCE.md)；项目采用 [MIT License](LICENSE)。
