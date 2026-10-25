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

- **找回历史**：自动记录文本、链接、代码、颜色值和图片；置顶项优先，快捷回复随后，普通历史按复制时间倒序；支持多关键词分词搜索与命中词高亮。
- **双栏实时预览与动作工坊（`⌘Y`）**：右侧实时预览完整正文、代码高亮、色块色卡、图片预览；内置中英互译、合并 PDF 断行、美化 JSON、提取验证码/单号、去空格、URL 解码，并支持在**动作工坊**中自由添加/编辑自定义 AI Prompt 指令或本地 Shell 脚本插件。
- **截图自动 Vision OCR 索引**：复制任何截图或图片后，后台自动使用 macOS 原生 `Vision` 引擎提取图中简繁中文与英文并建立搜索索引，直接输入截图内的文字即可搜出对应图片，也支持在预览栏一键提取文字或导出 PNG。
- **验证码与快递单号一键提取**：复制含验证码或单号的短信/邮件时，预览栏顶部自动弹出号码提取卡片，支持一键仅粘贴号码。
- **全局输入法短码自动展开**：为快捷回复或常用条目绑定如 `;dz`、`@mail` 等短码，在微信、浏览器或终端等任意输入框敲出短码即可原地自动替换为完整内容（支持 `{{date}}`、`{{time}}`、`{{clipboard}}` 动态占位符）。
- **智能推荐回复与自动归档（Local N-gram + Jev 引擎）**：自动按「地址与联系」「代码与命令」「验证码/单号」「外文内容」「工作沟通」语义归档，并在复制对方消息时智能推荐最匹配的快捷回复（`⌘R` 一键粘贴）。
- **即译即贴（`⌘T`）与连续粘贴（`⇧↵`）**：选中外文或中文按 `⌘T` 即刻翻译并粘贴；填表时按 `⇧↵` 可粘贴当前项并自动下移到下一条连续粘贴。
- **三种面板模式与外观定制**：支持粘贴后关闭、始终置顶、吸附到指定应用窗口；支持调节透明度（55%–100%）、强调色与内容密度。
- **隐私保护与数据备份**：支持一键暂停剪贴板记录、自定义敏感应用黑名单（默认排除钥匙串、密码、1Password、Bitwarden），以及快捷回复与动作配置的 JSON 导入/导出备份与数据库压缩瘦身。

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
| 呼出 / 收起面板 | `⇧⌘V` / `⌥⌘V` / `⌘D`（可在设置中切换） |
| 上下选择 / 分类切换 | `↑` / `↓` · `Tab` / `⇧Tab` |
| 粘贴选中内容 | `↵`（双击条目） |
| 连续粘贴并下移下一条 | `⇧↵` |
| 仅复制到剪贴板（不自动粘贴） | `⌘C` 或 `⌥↵` |
| 中英互译并直接粘贴 | `⌘T` |
| 粘贴智能推荐回复 | `⌘R` |
| 快速粘贴前 1–9 条 | `⌘1`–`⌘9`（`⌥⌘1`–`9` 仅复制） |
| 编辑条目 / 绑定输入法短码 | `⌘E` |
| 新建快捷回复 | `⌘N` |
| 展开 / 收起右侧预览栏 | `⌘Y` |
| 转为快捷回复 / 普通历史 | `⌥S` |
| 置顶 / 取消置顶 | `⌥P` |
| 删除选中条目 | `⌥⌫` |
| 清空筛选或收起面板 | `Esc` |

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
- 当前稳定版：**v2.0.0**
- 当前预编译包：**Apple Silicon / arm64**（提供 `.zip`、`.dmg` 与 `.sha256` 校验文件）

## 许可证

当前仓库尚未指定开源许可证。明确添加 `LICENSE` 文件前，请不要将项目标记为 MIT、Apache-2.0 或其他开源许可证。
