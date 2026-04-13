# OpenBoringBar Agent Guide

## 项目愿景

OpenBoringBar 的目标是做一个 [boringbar.app](https://boringbar.app) 的开源平替，优先覆盖「多显示器下的底部任务栏」体验。

## v1.0 目标与边界

### 必做功能

1. 每个显示器底部都有一条 bar（Windows 任务栏风格）。
2. 每条 bar 展示当前打开/运行中的应用列表（图标或名称）。
3. 点击应用项可以进行应用切换（激活对应 app 窗口）。

### 非目标（v1.0 不做）

1. 复杂动画主题系统。
2. 托盘插件生态。
3. 跨平台（先只做 macOS）。

## 技术方向

1. 平台：`macOS 14+`
2. 语言：`Swift 5`
3. UI：`SwiftUI` + `AppKit`（用于屏幕和应用窗口交互）
4. 工程管理：`CocoaPods`（`pod install` 自动生成/维护工程）

## 架构草图

1. `BarManager`：屏幕变化监听、运行中应用信息聚合、切换动作分发。
2. `BarWindowController`（后续）：为每个 `NSScreen` 管理一条置底 bar 窗口。
3. `AppSwitcher`（后续）：封装应用激活/窗口聚焦策略。
4. `UI`：按显示器渲染 bar 的展示层。

## 里程碑

1. `M1`：可编译工程 + 单窗口原型（本仓库当前状态）。
2. `M2`：多显示器 bar 窗口基础能力。
3. `M3`：真实运行应用列表 + 点击切换。
4. `M4`：稳定性和性能优化（显示器热插拔、睡眠唤醒场景）。

## 协作规则

1. 先保证可运行，再迭代视觉细节。
2. 新增功能必须可回归验证（最少给出手动验证步骤）。
3. 每次改动后先执行 `./scripts/bootstrap.sh`，再检查和处理编译问题。
4. 不要直接修改 `OpenBoringBar.xcodeproj`；如需更新源码引用，请改 `scripts/generate_xcodeproj.rb`（按 `OpenBoringBar/App/**/*.swift` 与 `OpenBoringBar/Core/**/*.swift` 自动收集）。
5. 修改 v1.0 范围时，先更新本文件与 `README.md`。
