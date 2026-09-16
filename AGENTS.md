# 项目约定

- 技术栈采用 Swift + AppKit。新增和优化界面使用 AppKit 原生控件，通过代码和 Auto Layout 构建布局；不引入 SwiftUI。
- 界面文案使用简体中文，颜色使用系统语义色，支持浅色与深色外观，保留键盘操作。
- 最低运行版本为 macOS 26，使用 AppKit 原生液态玻璃（`NSGlassEffectView`），跟随系统外观与辅助功能设置。构建使用 macOS 26 或更新的 SDK，无需旧系统兼容分支。
- 修改剪贴板行为、窗口交互或打包流程时，阅读 `MAINTENANCE.md` 中对应说明，并按其中的回归测试清单验证受影响的行为。
