<div align="center">

# Pomodoro Menubar · 番茄钟菜单栏 App

**A native macOS menu-bar Pomodoro timer in a single Swift file — 25 / 3 / 15 rhythm, a stand-up reminder every 45 minutes, and a draggable floating timer bar. No Xcode project, one script to build.**

[中文](README.md) | English

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-AppKit%20%2B%20SwiftUI-F05138?logo=swift&logoColor=white)
![Single file](https://img.shields.io/badge/source-single%20file-blue)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

</div>

## Features

- **Standard rhythm**: 25 min focus → 3 min short break, 15 min long break every 4 pomodoros; all durations configurable.
- **Stand-up reminder**: every 45 minutes, with a configurable activity length and snooze. This is the reason the app exists.
- **Floating timer bar**: a draggable bar on screen in S / M / L sizes (deliberately no free resize), adjustable opacity, remembers its position.
- **Morning / evening schedule**: optional auto-start time and end-of-day reminder.
- **Sounds**: pick a system sound, loop it or not; optionally show remaining time as menu-bar text.
- Notifications use `UserNotifications`, so the build script applies an ad-hoc code signature.
- Menu-bar only (`LSUIElement`), no Dock icon.

## Build

Requires Xcode Command Line Tools (`xcode-select --install`) and macOS 13+.

```bash
bash build.sh                 # produces ./番茄钟.app
cp -R 番茄钟.app ~/Desktop/
open 番茄钟.app
```

`build.sh` compiles `src/main.swift` with `swiftc -O`, copies `AppIcon.icns`, writes `Info.plist`, and runs `codesign --sign -`.

## Layout

```
src/main.swift      everything: settings keys, timer state machine, menu bar, floating bar, notifications, settings panel
src/icon_gen.swift  draws the 1024 px icon programmatically
AppIcon.iconset/    PNG sizes; AppIcon.icns built with iconutil
build.sh            one-shot build & package
```

Preferences live in `UserDefaults` (keys listed at the top of `main.swift`); deleting the app leaves nothing behind.

## License

MIT — see [LICENSE](LICENSE).
