import AppKit
import SwiftUI
import UserNotifications
import Combine

// MARK: - 设置 Keys & 默认值

enum Keys {
    static let workMinutes = "workMinutes"
    static let shortBreakMinutes = "shortBreakMinutes"
    static let longBreakMinutes = "longBreakMinutes"
    static let longBreakEvery = "longBreakEvery"
    static let standUpEnabled = "standUpEnabled"
    static let standUpIntervalMinutes = "standUpIntervalMinutes"
    static let activityMinutes = "activityMinutes"      // 站起来后活动几分钟
    static let snoozeMinutes = "snoozeMinutes"
    static let soundName = "soundName"
    static let loopSound = "loopSound"
    static let showInMenuBarText = "showInMenuBarText"
    static let enableSchedule = "enableSchedule"
    static let morningHour = "morningHour"
    static let morningMinute = "morningMinute"
    static let eveningHour = "eveningHour"
    static let eveningMinute = "eveningMinute"
    static let widgetX = "widgetX"
    static let widgetY = "widgetY"
    static let widgetW = "widgetW"        // 旧版遗留,不再使用,只在复位时清掉
    static let widgetH = "widgetH"
    static let widgetSize = "widgetSize"  // "S" / "M" / "L"
    static let widgetOpacity = "widgetOpacity"
    static let lastFiredMorning = "lastFiredMorning"
    static let lastFiredEvening = "lastFiredEvening"
}

func registerDefaults() {
    UserDefaults.standard.register(defaults: [
        Keys.workMinutes: 25,
        Keys.shortBreakMinutes: 3,
        Keys.longBreakMinutes: 15,
        Keys.longBreakEvery: 4,
        Keys.standUpEnabled: true,
        Keys.standUpIntervalMinutes: 45,
        Keys.activityMinutes: 3,
        Keys.snoozeMinutes: 5,
        Keys.soundName: "Glass",
        Keys.loopSound: true,
        Keys.showInMenuBarText: true,
        Keys.enableSchedule: true,
        Keys.morningHour: 9, Keys.morningMinute: 0,
        Keys.eveningHour: 20, Keys.eveningMinute: 0,
        Keys.widgetSize: "M",
        Keys.widgetOpacity: 0.72,
    ])
}

let availableSounds = ["Glass", "Ping", "Hero", "Submarine", "Funk", "Blow", "Bottle", "Frog", "Morse", "Purr", "Sosumi", "Tink"]

// MARK: - 横条尺寸预设(只允许三档,不开放自由缩放,杜绝"一条缝"bug)

enum WidgetSize: String, CaseIterable {
    case small = "S", medium = "M", large = "L"

    var w: CGFloat { switch self { case .small: return 215; case .medium: return 250; case .large: return 320 } }
    var h: CGFloat { switch self { case .small: return 54;  case .medium: return 66;  case .large: return 86 } }
    var label: String { switch self { case .small: return "小"; case .medium: return "中"; case .large: return "大" } }

    static var current: WidgetSize {
        WidgetSize(rawValue: UserDefaults.standard.string(forKey: Keys.widgetSize) ?? "M") ?? .medium
    }
}

// MARK: - 阶段

enum Phase {
    case work, shortBreak, longBreak, activity   // activity = 站起来走走后的活动段

    var isBreak: Bool { self != .work }
    var emoji: String {
        switch self { case .work: return "🍅"; case .shortBreak: return "☕️"; case .longBreak: return "🌴"; case .activity: return "🚶" }
    }
    var titleCN: String {
        switch self { case .work: return "专注"; case .shortBreak: return "短休"; case .longBreak: return "长休"; case .activity: return "活动" }
    }
    var color: Color {
        switch self {
        case .work:       return Color(red: 0.91, green: 0.25, blue: 0.20)
        case .shortBreak: return Color(red: 0.29, green: 0.61, blue: 0.24)
        case .longBreak:  return Color(red: 0.16, green: 0.50, blue: 0.73)
        case .activity:   return Color(red: 0.93, green: 0.55, blue: 0.14)
        }
    }
}

// MARK: - 计时器模型

final class TimerModel: ObservableObject {
    @Published var phase: Phase = .work
    @Published var remaining: Int = 0
    @Published var running = false
    @Published var completedWorkSessions = 0   // 累计完成的番茄数
    @Published var standUpElapsed = 0           // 距上次站起来,已连续运行的秒数(专注+休息都算)

    var timer: Timer?
    var onChange: (() -> Void)?
    var onWorkComplete: ((Int, Phase) -> Void)?   // (第几个番茄, 接下来的休息类型)
    var onBreakComplete: ((Phase) -> Void)?       // 休息结束 → 自动进下一番茄
    var onStandUpDue: (() -> Void)?               // 到 45 分钟 → 弹"站起来走走"

    private var defaults: UserDefaults { .standard }

    init() { remaining = duration(.work) }

    func duration(_ p: Phase) -> Int {
        switch p {
        case .work:       return max(1, defaults.integer(forKey: Keys.workMinutes)) * 60
        case .shortBreak: return max(1, defaults.integer(forKey: Keys.shortBreakMinutes)) * 60
        case .longBreak:  return max(1, defaults.integer(forKey: Keys.longBreakMinutes)) * 60
        case .activity:   return max(1, defaults.integer(forKey: Keys.activityMinutes)) * 60
        }
    }

    var longBreakEvery: Int { max(1, defaults.integer(forKey: Keys.longBreakEvery)) }
    // 本轮已完成几个(0...every-1);刚做完第 4 个、还在长休时显示满格
    var cycleDone: Int {
        if completedWorkSessions > 0 && completedWorkSessions % longBreakEvery == 0 && phase == .longBreak { return longBreakEvery }
        return completedWorkSessions % longBreakEvery
    }

    var standUpEnabled: Bool { defaults.bool(forKey: Keys.standUpEnabled) }
    var standUpTotal: Int { max(1, defaults.integer(forKey: Keys.standUpIntervalMinutes)) * 60 }
    var standUpRemaining: Int { max(0, standUpTotal - standUpElapsed) }

    var total: Int { duration(phase) }
    var progress: Double { total > 0 ? Double(total - remaining) / Double(total) : 0 }
    var timeString: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }

    private func changed() { objectWillChange.send(); onChange?() }

    func start() {
        guard !running else { return }
        running = true
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        changed()
    }
    func pause() { running = false; timer?.invalidate(); timer = nil; changed() }
    func toggle() { running ? pause() : start() }

    private func beginPhase(_ p: Phase) {
        pause()
        phase = p
        remaining = duration(p)
        changed()
        start()
    }

    // 开始一个全新的专注番茄(供定时/手动调用),不改累计数
    func startWorkSession() { beginPhase(.work) }

    // 重置本轮计数(从第 1 个番茄重新数)
    func resetCycle() {
        completedWorkSessions = 0
        changed()
    }

    // 刚完成第 n 个番茄后该休哪种
    private func breakAfterCompletion() -> Phase {
        completedWorkSessions % longBreakEvery == 0 ? .longBreak : .shortBreak
    }

    // 跳过当前段:专注→当作完成进休息;休息→直接进专注
    func skip() {
        if phase == .work {
            completedWorkSessions += 1
            beginPhase(breakAfterCompletion())
        } else {
            beginPhase(.work)
        }
    }

    // 我起来了 → 清零久坐计数,进入活动段(默认 3 分钟),活动结束自动开新番茄
    func standUpConfirmed() {
        standUpElapsed = 0
        beginPhase(.activity)
    }
    // 再坐几分钟 → 把计数拨到"再过 N 分钟就到"
    func standUpSnooze() {
        standUpElapsed = max(0, standUpTotal - max(1, defaults.integer(forKey: Keys.snoozeMinutes)) * 60)
        changed()
        start()
    }

    @objc func tick() {
        guard running else { return }
        remaining -= 1
        if remaining <= 0 {
            if phase == .work {
                completedWorkSessions += 1
                let next = breakAfterCompletion()
                onWorkComplete?(completedWorkSessions, next)
                beginPhase(next)
            } else {
                let finished = phase
                onBreakComplete?(finished)
                beginPhase(.work)
            }
        } else {
            changed()
        }

        // 站起来提醒:独立计时,专注/休息都在累计
        if standUpEnabled {
            standUpElapsed += 1
            if standUpElapsed >= standUpTotal {
                pause()                 // 番茄暂停,等用户走完回来点确认
                onStandUpDue?()
            }
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = TimerModel()
    var statusItem: NSStatusItem!
    var widget: WidgetController?
    var prefsWindow: NSWindow?
    var popupController: PopupController?
    var transient: TransientPopupController?
    var currentSound: NSSound?
    var scheduleTimer: Timer?

    var defaults: UserDefaults { .standard }

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerDefaults()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let menu = NSMenu(); menu.delegate = self
        statusItem.menu = menu

        model.onChange = { [weak self] in self?.updateStatusTitle() }
        model.onWorkComplete = { [weak self] n, next in
            guard let self else { return }
            let mins = self.model.duration(next) / 60
            let kind = next == .longBreak ? "长休" : "短休"
            self.notify("第 \(n) 个番茄完成 🍅", "\(kind) \(mins) 分钟,放松一下")
            self.playSound(loop: false)
            self.showTransient(emoji: next.emoji, title: "第 \(n) 个番茄完成！", body: "\(kind) \(mins) 分钟，放松一下", color: next.color)
        }
        model.onBreakComplete = { [weak self] finished in
            guard let self else { return }
            let work = self.defaults.integer(forKey: Keys.workMinutes)
            let what = finished == .activity ? "活动结束" : "休息结束"
            self.notify("\(what),开始下一个番茄 🍅", "坐下继续专注 \(work) 分钟")
            self.playSound(loop: false)
            self.showTransient(emoji: "🍅", title: "\(what)，开始下一个番茄", body: "专注 \(work) 分钟", color: Phase.work.color)
        }
        model.onStandUpDue = { [weak self] in
            guard let self else { return }
            let mins = self.model.standUpTotal / 60
            self.notify("该站起来走走了 🧍", "已连续坐了 \(mins) 分钟,起来走两步、喝口水")
            self.playSound(loop: self.defaults.bool(forKey: Keys.loopSound))
            self.showStandUpPopup()
        }
        updateStatusTitle()

        showWidget()   // 启动即显示,方便你看到 & 操作

        // 定时器:每 30 秒检查一次是否到点
        let st = Timer(timeInterval: 30, target: self, selector: #selector(checkSchedule), userInfo: nil, repeats: true)
        st.tolerance = 10
        RunLoop.main.add(st, forMode: .common)
        scheduleTimer = st

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // 双击 App 图标重新打开 → 显示横条
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWidget()
        return true
    }

    // MARK: 定时
    private func todayString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    @objc func checkSchedule() {
        guard defaults.bool(forKey: Keys.enableSchedule) else { return }
        let cal = Calendar.current
        let now = Date()
        let slots: [(h: Int, m: Int, key: String)] = [
            (defaults.integer(forKey: Keys.morningHour), defaults.integer(forKey: Keys.morningMinute), Keys.lastFiredMorning),
            (defaults.integer(forKey: Keys.eveningHour), defaults.integer(forKey: Keys.eveningMinute), Keys.lastFiredEvening),
        ]
        for slot in slots {
            guard let target = cal.date(bySettingHour: slot.h, minute: slot.m, second: 0, of: now) else { continue }
            let grace: TimeInterval = 15 * 60
            if now >= target && now < target.addingTimeInterval(grace) {
                if defaults.string(forKey: slot.key) != todayString() {
                    defaults.set(todayString(), forKey: slot.key)
                    fireScheduledSession()
                }
            }
        }
    }
    func fireScheduledSession() {
        showWidget()
        model.startWorkSession()
    }

    // MARK: 横条
    func showWidget() {
        if widget == nil {
            widget = WidgetController(model: model, actions: WidgetActions(
                onSettings: { [weak self] in self?.openPreferences() },
                onHide:     { [weak self] in self?.hideWidget() },
                onQuit:     { NSApp.terminate(nil) },
                onSetSize:  { [weak self] size in self?.applyWidgetSize(size) }
            ))
        }
        widget?.show()
    }
    func hideWidget() { model.pause(); widget?.close() }
    func toggleWidget() { widget?.isVisible == true ? hideWidget() : showWidget() }

    // 切换横条大小(⋯菜单 / 设置页调用)
    func applyWidgetSize(_ size: WidgetSize) {
        defaults.set(size.rawValue, forKey: Keys.widgetSize)
        widget?.applySize(size)
    }

    // 一键恢复横条(设置里调用):清掉存的位置,回默认右上角+当前档位尺寸并显示
    @objc func resetWidget() {
        defaults.removeObject(forKey: Keys.widgetX)
        defaults.removeObject(forKey: Keys.widgetY)
        defaults.removeObject(forKey: Keys.widgetW)
        defaults.removeObject(forKey: Keys.widgetH)
        showWidget()
        widget?.restoreDefault()
    }

    // MARK: 菜单栏标题
    func updateStatusTitle() {
        let showText = defaults.bool(forKey: Keys.showInMenuBarText)
        statusItem.button?.title = showText ? "\(model.phase.emoji) \(model.timeString)" : model.phase.emoji
    }

    // MARK: 声音
    func playSound(loop: Bool) {
        currentSound?.stop()
        let name = defaults.string(forKey: Keys.soundName) ?? "Glass"
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.loops = loop
            currentSound = sound
            sound.play()
        } else { NSSound.beep() }
    }
    func stopSound() { currentSound?.stop(); currentSound = nil }

    // MARK: 通知
    func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: 番茄切换小弹窗(只弹一下,几秒后自动消失,不抢焦点)
    func showTransient(emoji: String, title: String, body: String, color: Color) {
        transient?.close()
        let t = TransientPopupController(emoji: emoji, title: title, body: body, color: color)
        transient = t
        t.show(autoCloseAfter: 6)
    }

    // MARK: 站起来走走弹窗
    func showStandUpPopup() {
        transient?.close()
        popupController?.close()
        let c = PopupController(
            minutes: model.standUpTotal / 60,
            snoozeMinutes: max(1, defaults.integer(forKey: Keys.snoozeMinutes)),
            activityMinutes: max(1, defaults.integer(forKey: Keys.activityMinutes)),
            onConfirm: { [weak self] in self?.stopSound(); self?.popupController?.close(); self?.model.standUpConfirmed() },
            onSnooze:  { [weak self] in self?.stopSound(); self?.popupController?.close(); self?.model.standUpSnooze() }
        )
        popupController = c
        c.show()
    }

    // MARK: 菜单栏下拉(备用入口)
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = NSMenuItem(title: "\(model.phase.emoji) \(model.phase.titleCN)中 · 本轮 \(model.cycleDone)/\(model.longBreakEvery) · 累计 \(model.completedWorkSessions) 个番茄", action: nil, keyEquivalent: "")
        s.isEnabled = false; menu.addItem(s)
        if model.standUpEnabled {
            let m = (model.standUpRemaining + 59) / 60
            let u = NSMenuItem(title: "🧍 距下次站起提醒约 \(m) 分钟", action: nil, keyEquivalent: "")
            u.isEnabled = false; menu.addItem(u)
        }
        menu.addItem(.separator())
        add(menu, model.running ? "⏸ 暂停" : "▶️ 开始", #selector(menuToggle))
        add(menu, "⏭ 跳到下一段", #selector(menuSkip))
        add(menu, "🍅 开始新的番茄", #selector(menuStartWork))
        add(menu, "🔄 重置本轮计数", #selector(menuResetCycle))
        menu.addItem(.separator())
        add(menu, widget?.isVisible == true ? "🖥 隐藏横条" : "🖥 显示横条", #selector(menuToggleWidget))
        add(menu, "⚙️ 设置…", #selector(openPreferences), key: ",")
        add(menu, "退出", #selector(quit), key: "q")
    }
    private func add(_ menu: NSMenu, _ t: String, _ a: Selector, key: String = "") {
        let i = NSMenuItem(title: t, action: a, keyEquivalent: key); i.target = self; menu.addItem(i)
    }
    @objc func menuToggle() { model.toggle() }
    @objc func menuSkip() { model.skip() }
    @objc func menuStartWork() { showWidget(); model.startWorkSession() }
    @objc func menuResetCycle() { model.resetCycle() }
    @objc func menuToggleWidget() { toggleWidget() }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func openPreferences() {
        if prefsWindow == nil {
            let hosting = NSHostingController(rootView: PreferencesView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "番茄钟 · 设置"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            prefsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        prefsWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 横条控制器

struct WidgetActions {
    var onSettings: () -> Void
    var onHide: () -> Void
    var onQuit: () -> Void
    var onSetSize: (WidgetSize) -> Void
}

class WidgetController: NSObject {
    // 尺寸只来自三档预设,横条本身不可拖拽缩放
    private(set) var size: WidgetSize = .current

    let panel: NSPanel
    let model: TimerModel

    init(model: TimerModel, actions: WidgetActions) {
        self.model = model
        let d = UserDefaults.standard
        let sz = WidgetSize.current
        size = sz
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: sz.w, height: sz.h),
                        styleMask: [.borderless, .nonactivatingPanel],   // 无 .resizable → 不可缩放
                        backing: .buffered, defer: false)
        super.init()

        let hosting = NSHostingView(rootView: WidgetBarView(model: model, actions: actions))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true      // 仍可拖动改位置,只是不能缩放
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false

        if d.object(forKey: Keys.widgetX) != nil {
            panel.setFrameOrigin(NSPoint(x: d.double(forKey: Keys.widgetX), y: d.double(forKey: Keys.widgetY)))
        } else if let vf = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.maxX - sz.w - 40, y: vf.maxY - sz.h - 40))
        }

        // 尺寸固定,只在移动后保存位置(不监听 resize,不会有塌陷回调污染存档)
        NotificationCenter.default.addObserver(self, selector: #selector(saveFrame), name: NSWindow.didMoveNotification, object: panel)
    }

    @objc func saveFrame() {
        guard panel.isVisible else { return }
        let d = UserDefaults.standard
        d.set(Double(panel.frame.origin.x), forKey: Keys.widgetX)
        d.set(Double(panel.frame.origin.y), forKey: Keys.widgetY)
    }

    // 把 frame 夹回屏幕可见区域内
    private func clamped(_ f: NSRect) -> NSRect {
        guard let vf = (NSScreen.screens.first { $0.frame.intersects(f) } ?? NSScreen.main)?.visibleFrame else { return f }
        var r = f
        r.origin.x = min(max(r.origin.x, vf.minX), max(vf.minX, vf.maxX - r.width))
        r.origin.y = min(max(r.origin.y, vf.minY), max(vf.minY, vf.maxY - r.height))
        return r
    }

    // 每次显示前强制回到当前档位尺寸,任何情况下都不会再是"一条缝"
    private func enforceSize() {
        var f = panel.frame
        if abs(f.size.width - size.w) > 0.5 || abs(f.size.height - size.h) > 0.5 {
            f.origin.y += (f.size.height - size.h)   // 顶边固定
            f.size = NSSize(width: size.w, height: size.h)
            panel.setFrame(clamped(f), display: true)
        }
    }

    // 切档:以右上角为锚点缩放(横条一般贴右上,放大不会跑出屏幕),再夹回屏幕内
    func applySize(_ s: WidgetSize) {
        size = s
        var f = panel.frame
        f.origin.x += (f.size.width - s.w)
        f.origin.y += (f.size.height - s.h)
        f.size = NSSize(width: s.w, height: s.h)
        panel.setFrame(clamped(f), display: true, animate: true)
        saveFrame()
    }

    // 一键恢复:回默认位置(右上角)+当前档位尺寸并显示
    func restoreDefault() {
        var f = panel.frame
        f.size = NSSize(width: size.w, height: size.h)
        if let vf = NSScreen.main?.visibleFrame {
            f.origin = NSPoint(x: vf.maxX - size.w - 40, y: vf.maxY - size.h - 40)
        }
        panel.setFrame(f, display: true)
        panel.orderFrontRegardless()
        saveFrame()
    }

    var isVisible: Bool { panel.isVisible }
    func show() {
        enforceSize()
        // 位置跑到所有屏幕之外(换分辩率/拔外接屏)→ 自动拉回当前主屏右上角
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
        if !onScreen { restoreDefault(); return }
        panel.orderFrontRegardless()
    }
    func close() { panel.orderOut(nil) }
}

// MARK: - 横条视图(透明,按高度等比缩放)

struct WidgetBarView: View {
    @ObservedObject var model: TimerModel
    let actions: WidgetActions
    @AppStorage(Keys.widgetOpacity) var opacity = 0.72
    @AppStorage(Keys.widgetSize) var sizeRaw = "M"

    var body: some View {
        GeometryReader { geo in
            let s = min(max(geo.size.height / 66.0, 0.7), 2.2)
            HStack(spacing: 10 * s) {
                Text(model.phase.emoji).font(.system(size: 22 * s))

                VStack(alignment: .leading, spacing: 2 * s) {
                    HStack(spacing: 5 * s) {
                        Text(model.phase.titleCN)
                            .font(.system(size: 10 * s, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.5))
                        // 本轮进度点:●●○○ 表示 4 个一循环
                        HStack(spacing: 2.5 * s) {
                            ForEach(0..<model.longBreakEvery, id: \.self) { i in
                                Circle()
                                    .fill(i < model.cycleDone ? Phase.work.color : Color.black.opacity(0.18))
                                    .frame(width: 5 * s, height: 5 * s)
                            }
                        }
                    }
                    Text(model.timeString)
                        .font(.system(size: 24 * s, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(model.phase.color)
                }
                .fixedSize()

                Spacer(minLength: 4 * s)

                Button(action: { model.toggle() }) {
                    Image(systemName: model.running ? "pause.fill" : "play.fill")
                        .font(.system(size: 15 * s, weight: .bold))
                        .frame(width: 30 * s, height: 26 * s)
                }
                .buttonStyle(.borderedProminent).tint(model.phase.color)

                Button(action: { model.skip() }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 13 * s))
                        .foregroundStyle(Color.black.opacity(0.6))
                }.buttonStyle(.borderless)

                Menu {
                    Button("⚙️ 设置…", action: actions.onSettings)
                    Menu("📐 横条大小") {
                        ForEach(WidgetSize.allCases, id: \.self) { sz in
                            Button((sz.rawValue == sizeRaw ? "✓ " : "    ") + sz.label + "（\(Int(sz.w))×\(Int(sz.h))）") {
                                actions.onSetSize(sz)
                            }
                        }
                    }
                    Divider()
                    Button("🍅 立即开始新番茄", action: { model.startWorkSession() })
                    Button("🔄 重置本轮计数", action: { model.resetCycle() })
                    if model.standUpEnabled {
                        Text("🧍 距站起提醒约 \((model.standUpRemaining + 59) / 60) 分钟")
                    }
                    Divider()
                    Button("🖥 隐藏横条", action: actions.onHide)
                    Divider()
                    Button("退出程序", action: actions.onQuit)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14 * s))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22 * s)
            }
            .padding(.horizontal, 12 * s)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 16 * s)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16 * s)
                        .fill(Color.white.opacity(0.55))
                    GeometryReader { g in
                        Rectangle()
                            .fill(model.phase.color.opacity(0.85))
                            .frame(width: g.size.width * model.progress, height: 3 * s)
                            .animation(.linear(duration: 0.3), value: model.progress)
                    }
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16 * s))
            )
            .overlay(RoundedRectangle(cornerRadius: 16 * s).strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
            .opacity(opacity)
            .contextMenu {
                Button("⚙️ 设置…", action: actions.onSettings)
                ForEach(WidgetSize.allCases, id: \.self) { sz in
                    Button("📐 横条：\(sz.label)" + (sz.rawValue == sizeRaw ? " ✓" : "")) { actions.onSetSize(sz) }
                }
                Button("🖥 隐藏横条", action: actions.onHide)
                Button("退出程序", action: actions.onQuit)
            }
        }
    }
}

// MARK: - 站起来走走弹窗

class PopupController {
    let window: NSWindow
    init(minutes: Int, snoozeMinutes: Int, activityMinutes: Int, onConfirm: @escaping () -> Void, onSnooze: @escaping () -> Void) {
        let view = StandUpPopupView(minutes: minutes, snoozeMinutes: snoozeMinutes, activityMinutes: activityMinutes, onConfirm: onConfirm, onSnooze: onSnooze)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 250)
        window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.center()
    }
    func show() {
        window.animationBehavior = .alertPanel
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func close() { window.orderOut(nil) }
}

struct StandUpPopupView: View {
    let minutes: Int
    let snoozeMinutes: Int
    let activityMinutes: Int
    let onConfirm: () -> Void
    let onSnooze: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Text("🧍").font(.system(size: 54))
            Text("该站起来走走了！")
                .font(.system(size: 19, weight: .bold))
            Text("已连续坐了 \(minutes) 分钟，起来走两步、喝口水、看看远处\n点「我起来了」→ 活动 \(activityMinutes) 分钟后自动开始下一个番茄")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button(action: onSnooze) { Text("再坐会儿（\(snoozeMinutes) 分钟）").frame(maxWidth: .infinity) }
                    .controlSize(.large)
                Button(action: onConfirm) { Text("✅ 我起来了").frame(maxWidth: .infinity) }
                    .controlSize(.large).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(26)
        .frame(width: 400, height: 250)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - 番茄切换小弹窗(非阻塞,自动消失)

class TransientPopupController {
    let panel: NSPanel
    var closeTimer: Timer?
    init(emoji: String, title: String, body: String, color: Color) {
        let hosting = NSHostingView(rootView: TransientPopupView(emoji: emoji, title: title, body: body, color: color))
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 92)
        panel = NSPanel(contentRect: hosting.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // 放在主屏顶部居中,不挡工作区中央
        if let vf = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.midX - hosting.frame.width / 2, y: vf.maxY - hosting.frame.height - 12))
        }
    }
    func show(autoCloseAfter seconds: TimeInterval) {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.25; panel.animator().alphaValue = 1 }
        closeTimer?.invalidate()
        closeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.close() }
    }
    func close() {
        closeTimer?.invalidate(); closeTimer = nil
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.3; panel.animator().alphaValue = 0 },
                                            completionHandler: { [panel] in panel.orderOut(nil) })
    }
}

struct TransientPopupView: View {
    let emoji: String
    let title: String
    let body_: String
    let color: Color
    init(emoji: String, title: String, body: String, color: Color) { self.emoji = emoji; self.title = title; self.body_ = body; self.color = color }
    var body: some View {
        HStack(spacing: 14) {
            Text(emoji).font(.system(size: 36))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(color)
                Text(body_).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(width: 340, height: 92)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(color.opacity(0.35), lineWidth: 1.5))
    }
}

// MARK: - 设置

struct PreferencesView: View {
    @AppStorage(Keys.workMinutes) var workMinutes = 25
    @AppStorage(Keys.shortBreakMinutes) var shortBreakMinutes = 5
    @AppStorage(Keys.longBreakMinutes) var longBreakMinutes = 15
    @AppStorage(Keys.longBreakEvery) var longBreakEvery = 4
    @AppStorage(Keys.standUpEnabled) var standUpEnabled = true
    @AppStorage(Keys.standUpIntervalMinutes) var standUpIntervalMinutes = 45
    @AppStorage(Keys.activityMinutes) var activityMinutes = 3
    @AppStorage(Keys.snoozeMinutes) var snoozeMinutes = 5
    @AppStorage(Keys.soundName) var soundName = "Glass"
    @AppStorage(Keys.loopSound) var loopSound = true
    @AppStorage(Keys.showInMenuBarText) var showInMenuBarText = true
    @AppStorage(Keys.enableSchedule) var enableSchedule = true
    @AppStorage(Keys.morningHour) var morningHour = 9
    @AppStorage(Keys.morningMinute) var morningMinute = 0
    @AppStorage(Keys.eveningHour) var eveningHour = 20
    @AppStorage(Keys.eveningMinute) var eveningMinute = 0
    @AppStorage(Keys.widgetOpacity) var widgetOpacity = 0.72
    @AppStorage(Keys.widgetSize) var widgetSize = "M"

    private func timeBinding(_ h: Binding<Int>, _ m: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                var c = DateComponents(); c.hour = h.wrappedValue; c.minute = m.wrappedValue
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                h.wrappedValue = c.hour ?? 9; m.wrappedValue = c.minute ?? 0
            })
    }

    var body: some View {
        Form {
            Section("番茄节奏（分钟）") {
                Stepper("专注：\(workMinutes)", value: $workMinutes, in: 1...120)
                Stepper("短休：\(shortBreakMinutes)", value: $shortBreakMinutes, in: 1...30)
                Stepper("长休：\(longBreakMinutes)", value: $longBreakMinutes, in: 1...60)
                Stepper("每 \(longBreakEvery) 个番茄后长休", value: $longBreakEvery, in: 2...8)
                Text("专注 25 → 短休 3，第 4 个番茄后长休 15，自动循环。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("站起来走走") {
                Toggle("到时间提醒我站起来", isOn: $standUpEnabled)
                Stepper("每 \(standUpIntervalMinutes) 分钟提醒一次", value: $standUpIntervalMinutes, in: 15...120, step: 5)
                    .disabled(!standUpEnabled)
                Stepper("「再坐会儿」时长：\(snoozeMinutes)", value: $snoozeMinutes, in: 1...30)
                    .disabled(!standUpEnabled)
                Stepper("起来后活动时长：\(activityMinutes)", value: $activityMinutes, in: 1...30)
                    .disabled(!standUpEnabled)
                Text("独立于番茄计时，专注和休息时间都在累计。提醒弹出时番茄暂停；点「我起来了」→ 活动倒计时 → 到点自动开始下一个番茄。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("自动定时") {
                Toggle("到点自动开始（其余时间不打扰）", isOn: $enableSchedule)
                DatePicker("早上时段", selection: timeBinding($morningHour, $morningMinute), displayedComponents: .hourAndMinute)
                DatePicker("晚上时段", selection: timeBinding($eveningHour, $eveningMinute), displayedComponents: .hourAndMinute)
            }
            Section("提醒") {
                Picker("提示音", selection: $soundName) {
                    ForEach(availableSounds, id: \.self) { Text($0).tag($0) }
                }
                Button("试听") { NSSound(named: NSSound.Name(soundName))?.play() }
                Toggle("站起提醒循环响铃直到我点确认", isOn: $loopSound)
            }
            Section("横条外观") {
                Picker("横条大小", selection: $widgetSize) {
                    ForEach(WidgetSize.allCases, id: \.self) { sz in
                        Text("\(sz.label) \(Int(sz.w))×\(Int(sz.h))").tag(sz.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: widgetSize) { raw in
                    if let sz = WidgetSize(rawValue: raw) { (NSApp.delegate as? AppDelegate)?.applyWidgetSize(sz) }
                }
                HStack {
                    Text("透明度")
                    Slider(value: $widgetOpacity, in: 0.3...1.0)
                    Text("\(Int(widgetOpacity * 100))%").monospacedDigit().frame(width: 42)
                }
                Toggle("菜单栏显示倒计时文字", isOn: $showInMenuBarText)
            }
            Section("横条出问题时") {
                Button {
                    (NSApp.delegate as? AppDelegate)?.resetWidget()
                } label: {
                    Label("🔧 一键恢复横条（回到右上角）", systemImage: "arrow.counterclockwise")
                }
                Text("横条不见了、位置跑偏或显示异常时，点这里即可复位。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 760)
    }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
