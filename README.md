# 剪贴板记录 · ClipHistory

一个轻量、注重隐私的 **macOS 菜单栏剪贴板历史工具**。自动记录你复制过的文本、链接和图片，随时用快捷键呼出面板，选一条即可粘贴到当前应用；还能把常用语句存成「快捷回复」。所有数据只保存在本机。

> 界面为中文本地化，应用名显示为「剪贴板记录」。

## 功能特性

- **自动记录** 复制的内容，并按时间倒序展示，重复内容自动去重并置顶。
- **内容分类**：自动识别 **文本 / 链接 / 图片**，配合 **快捷回复** 共四类，顶部分类栏可一键筛选（带数量）。
- **图片支持**：捕获剪贴板中的图片（截图、网页图片等），本地存储并显示缩略图，按字节去重；粘贴时原样写回。
- **快捷回复**：把常用文字（地址、话术等）保存为可复用条目，与历史记录分开管理。
- **键盘优先**：呼出面板后用 `↑/↓` 选择、`↵` 粘贴，`⌘1–9` 直接粘贴第 N 条；当然也支持鼠标点击。
- **置顶与搜索**：重要条目可置顶，支持按标题/正文搜索。
- **面板显示方式**：粘贴后关闭 / 始终置顶 / 吸附到指定应用窗口。
- **自动清理**：按条数或天数清理历史；置顶项与快捷回复不会被清理。
- **精致且克制的动效**：分类切换滑动高亮、列表增删过渡、选中项自动滚动居中。
- **隐私优先**：数据仅存本机 SQLite；自动跳过密码管理器等标记为敏感的剪贴板内容。

## 系统要求

- macOS 14 (Sonoma) 及以上
- 构建需要 Xcode / Command Line Tools（含 Swift 6 工具链）

## 预编译下载

Apple Silicon Mac 可直接从 [GitHub Releases](https://github.com/deerweek/cliphistory/releases/latest) 下载 `ClipHistory-macos-arm64` 压缩包。首次运行仍需在 **系统设置 → 隐私与安全性 → 辅助功能** 中授权应用。

## 安装与运行

克隆仓库后，在 macOS 上运行打包脚本：

```bash
git clone https://github.com/deerweek/cliphistory.git
cd cliphistory
./scripts/package-app.sh
```

脚本会编译并把 `剪贴板记录.app` 安装到 `~/Applications/`，默认使用不需要证书或钥匙串权限的 ad-hoc 签名，并嵌入稳定的 Bundle ID designated requirement，因此同一路径重新编译后不会因为可执行文件 hash 变化而丢失辅助功能授权。首次启动后，请到 **系统设置 → 隐私与安全性 → 辅助功能** 勾选当前运行的这一份应用，这样选中条目才能自动粘贴（`⌘V`）。设置页会显示当前应用的实际路径，并可在 Finder 中定位它；旧版或其他目录里的同名应用授权不会自动套用。如果你有开发者签名，可通过 `CLIPHISTORY_CODESIGN_IDENTITY` 指定签名身份。

如果系统阻止脚本覆盖旧应用，可以先在 Finder 里删除旧的「剪贴板记录」，或者使用 `CLIPHISTORY_INSTALL_DEST=/自定义路径 ./scripts/package-app.sh`。只想生成应用而不安装时，使用 `CLIPHISTORY_SKIP_INSTALL=1 ./scripts/package-app.sh`。

也可以直接用 Swift Package Manager 构建可执行文件：

```bash
swift build            # 需要 macOS（依赖 AppKit / SwiftUI 等系统框架）
```

## 使用说明

- 用快捷键呼出面板（默认 `⌘D`，可在设置里改成 `⇧⌘D` 或 `⇧⌘V`）。
- 输入关键字可搜索；顶部分类栏可按 文本 / 链接 / 图片 / 快捷回复 筛选。
- 选中一条后按 `↵` 或直接点击即可粘贴到之前的应用。

### 快捷键

| 快捷键 | 作用 |
| --- | --- |
| `⌘D`（默认） | 呼出 / 收起面板 |
| `↑` / `↓` | 上下选择条目 |
| `↵` | 粘贴选中条目 |
| `⌘1`–`⌘9` | 直接粘贴列表中第 1–9 条 |
| `⌥⌫` | 删除选中条目 |
| `⌥P` | 置顶 / 取消置顶 |
| `Esc` | 返回上一页 / 收起面板 |

> 说明：面板搜索框始终聚焦，纯数字键会被当作搜索输入，因此快速粘贴使用 `⌘ + 数字`。

## 隐私

- 所有记录保存在本地 SQLite 数据库：`~/Library/Application Support/剪贴板记录/history.sqlite`。
- 不联网、不上传任何内容。
- 自动忽略被标记为敏感/瞬态的剪贴板类型（如 1Password 等密码管理器）。

## 项目结构

```
Package.swift                 SwiftPM 配置
Sources/
  ClipHistory/                跨平台核心库（存储、分类、去重、面板定位）
  CSQLite/                    Linux 上的 SQLite 系统模块映射
  ClipHistoryApp/             macOS 应用（AppKit + SwiftUI 面板、剪贴板监听、粘贴、快捷键）
Tests/ClipHistoryTests/       核心库单元测试
scripts/
  package-app.sh              编译 + 签名 + 安装到 ~/Applications（macOS）
  run-tests.sh                运行单元测试（macOS）
  run-tests-linux.sh          在 Linux 上运行核心库单元测试
```

## 开发与测试

核心库 `ClipHistory`（数据模型、内容分类、存储与去重、面板定位算法）是**平台无关**的，可在 macOS 或 Linux 上编译并测试；GUI 部分 `ClipHistoryApp` 依赖 Apple 框架，只能在 macOS 构建/运行。

- macOS 上运行测试：

  ```bash
  ./scripts/run-tests.sh
  ```

- Linux 上运行核心库测试（本仓库已配置 Cursor Cloud Agent 环境 `.cursor/environment.json`，会自动安装 Swift 工具链）：

  ```bash
  ./scripts/run-tests-linux.sh
  ```

跨平台做法：`Database.swift` / `PanelPlacement.swift` 通过 `#if canImport(...)` 条件导入，`Package.swift` 仅在 Linux 依赖 `CSQLite` 模块映射，从而在两端都能构建核心库。

## 许可证

尚未指定许可证。如需开源分发，请在仓库根目录添加合适的 `LICENSE` 文件。
