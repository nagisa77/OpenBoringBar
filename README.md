# OpenBoringBar

OpenBoringBar 是 [boringbar.app](https://boringbar.app) 的开源平替项目，目标先聚焦在 macOS 多显示器场景下的底部任务栏能力。

## v1.0 目标

1. 每个显示器底部都有一条 bar（Windows 任务栏风格）。
2. 展示当前打开/运行中的应用列表。
3. 支持点击切换到对应应用窗口。

## 环境要求

1. macOS（建议 14+）
2. Xcode 26 或更高版本
3. CocoaPods（已安装 `pod` 命令）

## 一键生成工程并编译

```bash
./scripts/bootstrap.sh
```

这个命令会自动完成：

1. `pod install`（触发 `Podfile`，自动生成 `OpenBoringBar.xcodeproj` 并产出 workspace）
2. `xcodebuild`（通过 `OpenBoringBar.xcodeproj` + `OpenBoringBar` scheme 编译 Debug 版本，产物在 `.build/DerivedData`）

## 手动命令

```bash
pod install
xcodebuild -project OpenBoringBar.xcodeproj -scheme OpenBoringBar -configuration Debug -sdk macosx -destination 'platform=macOS' build
```

## 当前仓库结构

```text
.
├── agent.md
├── Podfile
├── OpenBoringBar
│   ├── App
│   │   ├── MainWindowView.swift
│   │   └── OpenBoringBarApp.swift
│   ├── Core
│   │   └── Bar
│   │       └── BarManager.swift
│   └── Resources
│       └── Info.plist
└── scripts
    ├── bootstrap.sh
    └── generate_xcodeproj.rb
```

## Roadmap

1. 当前：单窗口原型 + 基础应用切换接口。
2. 下一步：为每个显示器创建独立 bar 窗口。
3. 后续：接入真实窗口/应用状态同步和更完整交互。

## 贡献

欢迎提 Issue / PR。建议先阅读 [agent.md](./agent.md) 再开始改动。
