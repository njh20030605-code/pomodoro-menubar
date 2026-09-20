<div align="center">

# 番茄钟 · Pomodoro Menubar

**原生 macOS 菜单栏番茄钟，单个 Swift 文件：25 / 3 / 15 节奏、每 45 分钟站起提醒、可拖动的悬浮计时横条。没有 Xcode 工程，一个脚本编译。**

中文 | [English](README.en.md)

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-AppKit%20%2B%20SwiftUI-F05138?logo=swift&logoColor=white)
![Single file](https://img.shields.io/badge/%E6%BA%90%E7%A0%81-%E5%8D%95%E6%96%87%E4%BB%B6-blue)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

</div>
原生 Swift（AppKit + SwiftUI）写的番茄钟，只住在菜单栏，不占 Dock。单文件源码，一条命令编译。

## 给谁用

- 用 Mac 工作、想要一个**不占 Dock、不弹窗打扰**的番茄钟的人。
- 久坐的人：每 45 分钟提醒站起来，是这个 App 存在的主要原因。
- 想学 **AppKit + SwiftUI 菜单栏 App** 怎么写的人：全部逻辑在一个 `main.swift` 里，`build.sh` 不依赖 Xcode 工程。

关键词：macOS · 菜单栏 · 番茄钟 · Pomodoro · Swift · 站立提醒 · 悬浮计时

## 功能

- **标准节奏**：专注 25 分钟 → 短休 3 分钟，每 4 个番茄一次 15 分钟长休；时长都可在设置里改。
- **站起来提醒**：每 45 分钟提醒起身活动，活动时长可设；可贪睡。
- **悬浮横条**：屏幕上一根可拖动的计时横条，S / M / L 三档大小（不做自由缩放），透明度可调，位置记忆。
- **早晚定时**：可设每天几点自动开始、几点收工提醒。
- **提示音**：系统音效可选、可循环；菜单栏可选是否显示剩余时间文字。
- 通知走系统 `UserNotifications`，需要一次 ad-hoc 签名（`build.sh` 已包含）。

## 编译

需要 Xcode Command Line Tools（`xcode-select --install`），macOS 13+。

```bash
bash build.sh          # 产出 ./番茄钟.app
cp -R 番茄钟.app ~/Desktop/   # 放到常用位置
open 番茄钟.app
```

`build.sh` 做的事：`swiftc -O` 编译 `src/main.swift` → 拷贝 `AppIcon.icns` → 写 `Info.plist`（`LSUIElement=1` 即菜单栏 App）→ `codesign --sign -`。

改完代码重新 `bash build.sh`，退出旧的再打开新的即可。

## 文件

```
src/main.swift      全部逻辑：设置键 / 计时状态机 / 菜单栏 / 悬浮条 / 通知 / 设置面板
src/icon_gen.swift  用代码画 1024px 图标的小脚本（产出 icon_1024.png）
AppIcon.iconset/    各尺寸 PNG；AppIcon.icns 由 iconutil 合成
build.sh            一键编译打包
```

所有偏好存在 `UserDefaults`（键名见 `main.swift` 顶部的 `Keys`），删 App 不影响系统。

## 许可

MIT，见 [LICENSE](LICENSE)。
