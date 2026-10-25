<div align="center">

<img src="docs/assets/icon.png" width="108" height="108" alt="ClipHistory App Icon" />

# ClipHistory 2.0 · 剪贴板记录

**A Native macOS Dual-Pane Smart Clipboard & Text Expansion Workbench**  
*Built with Swift 6, AppKit/SwiftUI, SQLite WAL, Apple Vision OCR, and a Pluggable AI/Shell Action Studio*

<p align="center">
  <a href="README.md"><strong>🇨🇳 简体中文</strong></a> &nbsp;·&nbsp;
  <a href="README_EN.md"><strong>🇺🇸 English</strong></a> &nbsp;·&nbsp;
  <a href="https://github.com/deerweek/cliphistory/releases/latest"><strong>⬇️ Download v2.0.0 (.dmg / .zip)</strong></a> &nbsp;·&nbsp;
  <a href="https://github.com/deerweek/cliphistory/issues"><strong>💬 Report Issue</strong></a>
</p>

<p align="center">
  <a href="https://github.com/deerweek/cliphistory/releases/latest"><img src="https://img.shields.io/badge/Release-v2.0.0-2674F2?style=flat-square&logo=github" alt="Release v2.0.0"></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B%20Sonoma-111111?style=flat-square&logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-0A84FF?style=flat-square&logo=apple&logoColor=white" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/Storage-Local%20SQLite%20WAL-2E8B57?style=flat-square&logo=sqlite&logoColor=white" alt="Local SQLite">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="MIT License"></a>
</p>

<br/>

<img src="docs/assets/hero-showcase.png" width="100%" alt="ClipHistory 2.0 macOS Dual-Pane Showcase" />

</div>

---

## ✨ Highlights

<p align="center">
  <img src="docs/assets/feature-grid.png" width="100%" alt="ClipHistory 2.0 Feature Grid" />
</p>

- **🖥 Dual-Pane Live Inspector (`⌘Y`)**: Browse your clipboard history on the left while inspecting full multi-line text, monospaced code, `#HEX` color swatches, domain cards, and high-resolution images on the right—with real-time multi-keyword search highlighting.
- **⌨️ System-Wide `;trigger` Text Expander**: Bind short trigger codes (e.g. `;dz`, `@mail`, `:tax`) to frequently used snippets. Type the trigger code in any macOS app (WeChat, Slack, Safari, Xcode, Terminal) to expand it inline, complete with `{{date}}`, `{{time}}`, and `{{clipboard}}` template placeholders.
- **🔍 Automatic Apple Vision Screenshot OCR**: Every copied image or screenshot is silently indexed in the background using macOS's native `Vision` framework (`zh-Hans`, `zh-Hant`, `en-US`). Search for any word or invoice number inside a screenshot to find it immediately, or extract/export with one click.
- **⚡ Smart Reply (`⌘R`) & One-Click OTP Extraction**: Automatically classifies copied items into semantic archive tags (*Address & Contact*, *Code & Command*, *OTP / Tracking*, *Foreign Text*, *Work Chat*), surfaces a one-click banner for 4–8 digit verification codes, and recommends matching quick-reply snippets.
- **🪄 Pluggable Action Studio (`⌘T` Instant Translate)**: Includes built-in zero-config EN↔ZH translation, PDF line-wrap cleaner, JSON pretty-printer, whitespace stripper, and URL decoder—plus an **Action Studio** where you can create and edit custom AI Prompt transformations or local Shell scripts.
- **🛡 Privacy-First & Sequential Paste (`⇧↵`)**: 100% local SQLite WAL database, one-click recording pause, customizable app exclusion list (excludes Keychain, Passwords, 1Password, and Bitwarden by default), JSON backup import/export, and `⇧↵` sequential paste-and-advance for rapid form filling.

---

## 🚀 Quick Start

### 1. Download Prebuilt App

Download [**ClipHistory-macos-arm64-v2.0.0.dmg**](https://github.com/deerweek/cliphistory/releases/download/v2.0.0/ClipHistory-macos-arm64-v2.0.0.dmg) or [**ClipHistory-macos-arm64-v2.0.0.zip**](https://github.com/deerweek/cliphistory/releases/download/v2.0.0/ClipHistory-macos-arm64-v2.0.0.zip) from [GitHub Releases](https://github.com/deerweek/cliphistory/releases/latest), move `剪贴板记录.app` into `~/Applications`, and grant **Accessibility** permission in **System Settings → Privacy & Security → Accessibility**.

### 2. Build from Source

```bash
git clone https://github.com/deerweek/cliphistory.git
cd cliphistory
./scripts/run-tests.sh
./scripts/package-app.sh && open ~/Applications/剪贴板记录.app
```

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>V</kbd> / <kbd>⌘</kbd> <kbd>D</kbd> | Toggle ClipHistory floating panel |
| <kbd>↑</kbd> / <kbd>↓</kbd> · <kbd>Tab</kbd> / <kbd>⇧</kbd> <kbd>Tab</kbd> | Navigate items · Cycle categories |
| <kbd>↵</kbd> (or Double-Click) | Paste selected item into target application |
| <kbd>⇧</kbd> <kbd>↵</kbd> | **Sequential Paste**: paste current item, keep panel open & advance to next row |
| <kbd>⌘</kbd> <kbd>T</kbd> | **Instant Translate & Paste** (EN ↔ ZH) |
| <kbd>⌘</kbd> <kbd>R</kbd> | Paste recommended quick-reply snippet |
| <kbd>⌘</kbd> <kbd>1</kbd> … <kbd>⌘</kbd> <kbd>9</kbd> | Paste item #1–#9 directly (hold <kbd>⌥</kbd> to copy only) |
| <kbd>⌘</kbd> <kbd>C</kbd> / <kbd>⌥</kbd> <kbd>↵</kbd> | Copy selected item to clipboard without pasting |
| <kbd>⌘</kbd> <kbd>E</kbd> / <kbd>⌘</kbd> <kbd>N</kbd> | Edit selected item & `;trigger` code / New snippet |
| <kbd>⌘</kbd> <kbd>Y</kbd> | Toggle Live Inspector preview pane |
| <kbd>⌥</kbd> <kbd>S</kbd> / <kbd>⌥</kbd> <kbd>P</kbd> / <kbd>⌥</kbd> <kbd>⌫</kbd> | Convert to snippet / Pin item / Delete item |

---

## 📄 License

Released under the [MIT License](LICENSE).
