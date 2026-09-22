# 剪贴板记录 · ClipHistory

<p align="center">
  <strong>找回你复制过的每一段内容，并把它送回刚才的应用。</strong>
  <br>
  一款轻量、隐私优先的 macOS 菜单栏剪贴板历史工具。
</p>

<p align="center">
  <a href="https://github.com/deerweek/cliphistory/releases/latest">下载最新版</a> ·
  <a href="https://github.com/deerweek/cliphistory/issues">报告问题</a> ·
  <a href="https://github.com/deerweek/cliphistory/releases">查看版本</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-2674F2?logo=apple&logoColor=white" alt="Apple Silicon arm64">
  <img src="https://img.shields.io/badge/data-local%20only-2E8B57" alt="Local data only">
</p>

剪贴板记录常驻菜单栏，自动保存复制过的文本、链接和图片。按下快捷键呼出面板，搜索或选择一条记录后，应用会尝试把它粘贴回打开面板前的聊天框、编辑器或浏览器。常用内容还可以保存成快捷回复，反复使用。

## 你可以用它做什么

- **找回历史**：自动记录文本、链接和图片；置顶项优先，快捷回复随后，普通历史按更新时间倒序；重复内容会自动去重并更新时间。
- **快速筛选**：按文本、链接、图片或快捷回复分类，也可以搜索标题和正文。
- **直接粘贴**：用鼠标点击、`↑/↓` + `↵`，或 `⌘1–9` 选择内容；应用会把内容写回系统剪贴板，并向目标应用发送 `⌘V`。
- **快捷回复**：把地址、客服话术、代码片段等保存成有标题的常用内容。
- **三种面板模式**：粘贴后关闭、始终置顶、吸附到指定应用窗口。
- **外观可调**：在“设置 → 外观”中选择透明度（55%–100%）、强调色和内容密度，修改会立即生效。
- **吸附跟随**：吸附模式会跟随目标应用的主窗口移动，面板按目标窗口层级显示；切换到其他应用后，其他窗口可以覆盖它。
- **置顶与清理**：重要内容可以置顶；历史可按条数或保存天数自动清理，置顶项和快捷回复不会被清理。
- **菜单栏常驻**：支持登录时启动，默认快捷键为 `⌘D`，也可以改为 `⇧⌘D` 或 `⇧⌘V`。

> 当前 Release 提供 Apple Silicon（arm64）构建，最低支持 macOS 14 Sonoma。

## 30 秒开始使用

### 直接下载

1. 打开 [GitHub Releases](https://github.com/deerweek/cliphistory/releases/latest)，下载 `ClipHistory-macos-arm64-*.zip`。
2. 解压，把 `剪贴板记录.app` 放入 `~/Applications/`，然后启动它。
3. 第一次启动时，打开 **系统设置 → 隐私与安全性 → 辅助功能**，勾选当前运行的这份 `剪贴板记录.app`。
4. 复制一段文本，按 `⌘D` 呼出面板，选择记录并按回车。

### 辅助功能权限

辅助功能权限用于两件事：把选中的内容自动粘贴到目标应用，以及在“吸附到应用”模式下读取目标窗口的位置。请授权设置页中显示的**当前运行路径**，默认路径是：

```text
~/Applications/剪贴板记录.app
```

macOS 会把不同路径下的同名应用当作不同副本。请不要同时运行桌面、下载目录和 `~/Applications` 中的多个副本；如果重新移动了应用，需要在辅助功能列表中重新勾选新路径对应的那一份。

没有辅助功能权限时，选择记录仍然会把内容写入系统剪贴板，但应用不会自动发送 `⌘V`；你可以在目标输入框中手动粘贴。设置页会显示授权状态、实际路径和当前版本，也提供打开系统设置、在 Finder 中定位应用和重新启动的按钮。

### 自动粘贴的目标

面板打开时，应用会先记住当时位于前台的其他应用。选择记录时，它会尝试把内容粘贴回这个应用；如果目标已经退出、没有可用窗口，或应用无法安全识别目标，则内容仍会留在系统剪贴板中，供手动粘贴。

## 常用快捷键

| 操作 | 快捷键 |
| --- | --- |
| 呼出 / 收起面板 | `⌘D`（默认） |
| 上下选择 | `↑` / `↓` |
| 粘贴选中内容 | `↵` |
| 快速粘贴前 1–9 条 | `⌘1`–`⌘9` |
| 删除选中条目 | `⌥⌫` |
| 置顶 / 取消置顶 | `⌥P` |
| 返回 / 收起 | `Esc` |

面板搜索框默认聚焦，因此数字键会输入搜索词；快速粘贴请使用 `⌘` + 数字。

## 内容与限制

- 文本最多保存 200,000 个字符。
- 图片会转换为 PNG 保存，单张图片超过 12 MB 时跳过记录。
- 当剪贴板同时包含文本和图片时，优先记录非空文本；只有没有可用文本时才记录图片。
- 链接包括常见的网页链接、邮箱地址、`ftp` / `mailto` 等链接形式。
- 被密码管理器标记为隐藏、瞬态或敏感的剪贴板内容会自动跳过。

## 隐私设计

- 应用运行时不联网，不上传剪贴板内容，也不依赖云服务。
- 历史和图片只保存在本机 SQLite 数据库：

  ```text
  ~/Library/Application Support/剪贴板记录/history.sqlite
  ```

- 自动粘贴使用当前应用的辅助功能权限，把选中内容写入系统剪贴板后向目标进程发送 `⌘V`。
- 不需要权限也可以查看、搜索和管理历史，只是需要手动完成最后一次粘贴。

## 从源码构建

### 环境要求

- macOS 14 Sonoma 或更高版本
- Xcode Command Line Tools
- Swift 6 工具链

当前构建脚本默认生成 Apple Silicon arm64 应用。如果要在 Intel Mac 上构建，可以覆盖目标架构：

```bash
TARGET=x86_64-apple-macos14.0 ./scripts/package-app.sh
```

如果本机 SDK 路径与脚本默认值不同，也可以同时指定 SDK：

```bash
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" ./scripts/package-app.sh
```

### 编译并安装

```bash
git clone https://github.com/deerweek/cliphistory.git
cd cliphistory
./scripts/package-app.sh
```

脚本会编译、签名并安装到：

```text
~/Applications/剪贴板记录.app
```

默认使用本地 ad-hoc 签名，不需要开发者证书或钥匙串权限；签名中包含稳定的 Bundle ID designated requirement，因此同一路径重新编译后不会仅因可执行文件 hash 变化而丢失辅助功能授权。如果你有开发者签名，可以指定：

```bash
CLIPHISTORY_CODESIGN_IDENTITY="你的签名身份" ./scripts/package-app.sh
```

只生成 `.app` 而不安装：

```bash
CLIPHISTORY_SKIP_INSTALL=1 ./scripts/package-app.sh
```

如果脚本无法覆盖旧应用，可以先在 Finder 中删除旧的「剪贴板记录」，或者指定完整的安装目标路径：

```bash
CLIPHISTORY_INSTALL_DEST="/自定义目录/剪贴板记录.app" ./scripts/package-app.sh
```

### 运行测试

核心库是平台无关的，macOS 和 Linux 都可以运行核心测试；菜单栏界面依赖 AppKit / SwiftUI，只能在 macOS 上构建和运行。

```bash
./scripts/run-tests.sh          # macOS，完整核心测试
./scripts/run-tests-linux.sh   # Linux，仅核心库测试
```

## 项目结构

```text
Package.swift
Sources/
  ClipHistory/                 平台无关核心：模型、SQLite、分类、去重、清理、布局算法
  CSQLite/                     Linux 的 SQLite 系统模块映射
  ClipHistoryApp/              macOS 菜单栏应用、SwiftUI 面板、监听、粘贴和快捷键
Tests/ClipHistoryTests/         核心库测试
scripts/
  package-app.sh               编译、签名并安装 macOS 应用
  signing.sh                   本地签名逻辑
  run-tests.sh                 macOS 测试
  run-tests-linux.sh           Linux 核心测试
```

## 下载与版本

- [下载最新版](https://github.com/deerweek/cliphistory/releases/latest)
- [查看全部 Releases](https://github.com/deerweek/cliphistory/releases)
- 当前稳定版：**v1.1.0**
- 当前预编译包：**Apple Silicon / arm64**
- 每个应用压缩包旁边提供 SHA-256 校验文件

## 许可证

当前仓库尚未指定开源许可证。明确添加 `LICENSE` 文件前，请不要将项目标记为 MIT、Apache-2.0 或其他开源许可证。
