import AppKit
import Foundation
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    let video = NSTextField()
    let audio = NSTextField()
    let output = NSTextField()
    let videoInfo = NSTextField(labelWithString: "选择包含画面的视频文件")
    let audioInfo = NSTextField(labelWithString: "选择对应的音频文件")
    let status = NSTextField(labelWithString: "准备合并")
    let detail = NSTextField(labelWithString: "在本机处理，保留原有画质与音质。")
    let progress = NSProgressIndicator()
    let logView = NSTextView()
    var startButton: NSButton!
    var checkButton: NSButton!
    var cancelButton: NSButton!
    var revealButton: NSButton!
    var playButton: NSButton!
    var pickers: [NSButton] = []
    var process: Process?
    var busy = false
    var merging = false
    var terminalEvent = false
    var closeWhenFinished = false
    var resultURL: URL?
    var appStarted = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        setupMenu()
        setupWindow()
        for (field, key) in [(video, "video"), (audio, "audio"), (output, "output")] {
            // Clear the path preferences written by versions 1.0 and 1.0.1.
            UserDefaults.standard.removeObject(forKey: key)
            field.stringValue = ""
            field.delegate = self
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setupMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 M4S 合并器", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 M4S 合并器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem()
        editItem.title = "编辑"
        menu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"),
                                      ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = menu
    }

    func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let result = NSTextField(labelWithString: text)
        result.font = .systemFont(ofSize: size, weight: weight)
        result.textColor = secondary ? .secondaryLabelColor : .labelColor
        result.lineBreakMode = .byWordWrapping
        result.maximumNumberOfLines = 0
        return result
    }

    func stack(_ views: [NSView], vertical: Bool = true, spacing: CGFloat = 8) -> NSStackView {
        let result = NSStackView(views: views)
        result.orientation = vertical ? .vertical : .horizontal
        result.alignment = vertical ? .leading : .centerY
        result.spacing = spacing
        return result
    }

    func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .large
        b.font = .systemFont(ofSize: 13)
        b.setContentHuggingPriority(.required, for: .horizontal)
        return b
    }

    func fill(_ view: NSView, in parent: NSView) {
        view.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
    }

    func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    func fileRow(_ title: String, field: NSTextField, info: NSTextField, action: Selector, symbol: String) -> NSStackView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let heading = stack([icon, label(title, weight: .semibold)], vertical: false, spacing: 7)
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingMiddle
        field.placeholderString = "选择文件，或粘贴完整路径"
        field.setAccessibilityLabel(title + "路径")
        field.heightAnchor.constraint(equalToConstant: 28).isActive = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let choose = button("选择文件…", action)
        pickers.append(choose)
        let row = stack([field, choose], vertical: false, spacing: 10)
        info.font = .systemFont(ofSize: 12)
        info.textColor = .secondaryLabelColor
        info.lineBreakMode = .byTruncatingTail
        let section = stack([heading, row, info], spacing: 7)
        fill(row, in: section)
        fill(info, in: section)
        return section
    }

    func setupWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 690),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "M4S 合并器"
        window.minSize = NSSize(width: 720, height: 700)
        window.delegate = self
        window.isReleasedWhenClosed = false
        let root = window.contentView!
        let main = stack([], spacing: 19)
        main.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(main)
        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            main.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            main.topAnchor.constraint(equalTo: root.topAnchor, constant: 26),
            main.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24)
        ])
        let intro = stack([label("让画面和声音重新相遇", size: 24, weight: .semibold),
                           label("将分离的 M4S 视频与音频合并为一个 MP4。", secondary: true)], spacing: 7)
        main.addArrangedSubview(intro)
        let v = fileRow("视频", field: video, info: videoInfo, action: #selector(chooseVideo), symbol: "film")
        let a = fileRow("音频", field: audio, info: audioInfo, action: #selector(chooseAudio), symbol: "waveform")
        for row in [v, a] { main.addArrangedSubview(row); fill(row, in: main) }
        let sep = separator()
        main.addArrangedSubview(sep); fill(sep, in: main)
        output.font = .systemFont(ofSize: 13)
        output.lineBreakMode = .byTruncatingMiddle
        output.heightAnchor.constraint(equalToConstant: 28).isActive = true
        output.placeholderString = "选择 MP4 的保存位置"
        output.setAccessibilityLabel("MP4 保存路径")
        output.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let save = button("保存到…", #selector(chooseOutput))
        pickers.append(save)
        let saveRow = stack([output, save], vertical: false, spacing: 10)
        let saveSection = stack([label("保存为", weight: .semibold), saveRow,
                                  label("原文件会保留；已有的输出文件不会被覆盖。", size: 12, secondary: true)], spacing: 7)
        fill(saveRow, in: saveSection)
        main.addArrangedSubview(saveSection); fill(saveSection, in: main)
        status.font = .systemFont(ofSize: 14, weight: .medium)
        status.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        let progressSection = stack([status, progress, detail], spacing: 7)
        for item in [status, progress, detail] { fill(item, in: progressSection) }
        main.addArrangedSubview(progressSection); fill(progressSection, in: main)
        startButton = button("开始合并", #selector(start))
        startButton.keyEquivalent = "\r"
        startButton.bezelColor = .controlAccentColor
        checkButton = button("检查文件", #selector(inspect))
        cancelButton = button("取消", #selector(cancel))
        cancelButton.isEnabled = false
        cancelButton.keyEquivalent = "\u{1b}"
        revealButton = button("在 Finder 中显示", #selector(reveal))
        playButton = button("播放视频", #selector(play))
        revealButton.isHidden = true
        playButton.isHidden = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = stack([checkButton, cancelButton, spacer, revealButton, playButton, startButton], vertical: false, spacing: 8)
        main.addArrangedSubview(actions); fill(actions, in: main)
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.heightAnchor.constraint(equalToConstant: 82).isActive = true
        logView.isEditable = false
        logView.isSelectable = true
        logView.font = .systemFont(ofSize: 11)
        logView.textColor = .secondaryLabelColor
        logView.backgroundColor = .textBackgroundColor
        logView.textContainerInset = NSSize(width: 8, height: 7)
        logView.autoresizingMask = [.width]
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = false
        logView.textContainer?.widthTracksTextView = true
        logView.setAccessibilityLabel("处理记录")
        scroll.documentView = logView
        main.addArrangedSubview(scroll); fill(scroll, in: main)
        log("所有处理均在本机完成，文件不会上传。")
    }

    func log(_ text: String) {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
        let entry = formatter.string(from: Date()) + "  " + text + "\n"
        logView.textStorage?.append(NSAttributedString(string: entry, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        if logView.string.count > 16000 {
            logView.textStorage?.deleteCharacters(in: NSRange(location: 0, length: 4000))
        }
        logView.scrollToEndOfDocument(nil)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard !busy else { return }
        status.stringValue = "文件已更改，合并前会重新检查"
        status.textColor = .labelColor
        videoInfo.stringValue = "合并前会检查视频信息"
        audioInfo.stringValue = "合并前会检查音频信息"
        progress.doubleValue = 0
        revealButton.isHidden = true; playButton.isHidden = true
    }

    func selectFile(_ field: NSTextField, title: String) {
        let panel = NSOpenPanel()
        panel.title = title; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if !field.stringValue.isEmpty { panel.directoryURL = URL(fileURLWithPath: field.stringValue).deletingLastPathComponent() }
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                field.stringValue = url.path
                if !self.video.stringValue.isEmpty && !self.audio.stringValue.isEmpty { self.inspect() }
            }
        }
    }
    @objc func chooseVideo() { selectFile(video, title: "选择视频文件") }
    @objc func chooseAudio() { selectFile(audio, title: "选择音频文件") }
    @objc func chooseOutput() {
        let panel = NSSavePanel()
        panel.title = "保存合并后的视频"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        let url = URL(fileURLWithPath: output.stringValue.isEmpty ? NSHomeDirectory() + "/Movies/合并视频.mp4" : output.stringValue)
        panel.directoryURL = url.deletingLastPathComponent()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let selected = panel.url { self.output.stringValue = selected.path }
        }
    }

    func setBusy(_ value: Bool) {
        busy = value
        for field in [video, audio, output] { field.isEnabled = !value }
        for b in pickers { b.isEnabled = !value }
        startButton.isEnabled = !value; checkButton.isEnabled = !value
        cancelButton.isEnabled = value
    }

    func python() -> String? {
        let candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/Library/Frameworks/Python.framework/Versions/Current/bin/python3", "/usr/bin/python3"]
        return candidates.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }

    @objc func inspect() { launch(inspectOnly: true) }
    @objc func start() { launch(inspectOnly: false) }

    func launch(inspectOnly: Bool) {
        guard !busy else { return }
        window.makeFirstResponder(nil)
        guard !video.stringValue.isEmpty, !audio.stringValue.isEmpty else { fail("请先选择视频和音频文件。"); return }
        guard inspectOnly || !output.stringValue.isEmpty else { fail("请选择 MP4 的保存位置。"); return }
        guard let pythonPath = python(), let helper = Bundle.main.path(forResource: "merger", ofType: "py") else {
            fail("无法找到 Python 3 或处理组件，请检查应用是否完整。"); return
        }
        terminalEvent = false; merging = !inspectOnly
        resultURL = nil
        revealButton.isHidden = true; playButton.isHidden = true
        appStarted = Date()
        status.textColor = .labelColor
        status.stringValue = inspectOnly ? "正在检查文件…" : "准备合并…"
        detail.stringValue = "正在读取媒体信息，请稍候。"
        progress.doubleValue = 0
        progress.isIndeterminate = true; progress.startAnimation(nil)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: pythonPath)
        var args = ["-u", helper, "--video", video.stringValue, "--audio", audio.stringValue]
        args += inspectOnly ? ["--inspect"] : ["--output", output.stringValue]
        task.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PYTHONUNBUFFERED"] = "1"
        task.environment = env
        let pipe = Pipe()
        task.standardOutput = pipe; task.standardError = pipe
        task.standardInput = FileHandle.nullDevice
        do { try task.run() }
        catch { fail("无法启动处理程序：" + error.localizedDescription); return }
        process = task; setBusy(true)
        log(inspectOnly ? "检查视频与音频轨道。" : "开始合并；仅复制音视频轨道，不重新编码。")
        DispatchQueue.global(qos: .userInitiated).async {
            var buffer = Data()
            let handle = pipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let range = buffer.range(of: Data([10])) {
                    let line = buffer.subdata(in: 0..<range.lowerBound)
                    buffer.removeSubrange(0..<range.upperBound)
                    if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                        DispatchQueue.main.async { self.receive(object) }
                    } else if let text = String(data: line, encoding: .utf8), !text.isEmpty {
                        DispatchQueue.main.async { self.log(text) }
                    }
                }
            }
            task.waitUntilExit()
            DispatchQueue.main.async {
                self.process = nil
                self.setBusy(false)
                self.progress.stopAnimation(nil); self.progress.isIndeterminate = false
                if !self.terminalEvent {
                    if task.terminationStatus == 0 && inspectOnly {
                        self.status.stringValue = "文件检查通过，可以合并"
                        self.detail.stringValue = "将原有音视频轨道直接写入 MP4，文件大小接近两者之和。"
                    } else { self.fail("处理程序意外退出。请查看下方记录后重试。") }
                }
                self.merging = false
                if self.closeWhenFinished { NSApp.terminate(nil) }
            }
        }
    }

    func receive(_ event: [String: Any]) {
        guard let kind = event["event"] as? String else { return }
        switch kind {
        case "info":
            let vb = (event["video_bytes"] as? NSNumber)?.int64Value ?? 0
            let ab = (event["audio_bytes"] as? NSNumber)?.int64Value ?? 0
            let seconds = (event["duration"] as? Double) ?? 0
            let duration = String(format: "%02d:%02d:%02d", Int(seconds) / 3600, Int(seconds) / 60 % 60, Int(seconds) % 60)
            videoInfo.stringValue = "\(event["width"] ?? "") × \(event["height"] ?? "")  ·  \(String(describing: event["video_codec"] ?? "").uppercased())  ·  \(size(vb))  ·  \(duration)"
            audioInfo.stringValue = "\(String(describing: event["audio_codec"] ?? "").uppercased())  ·  \(event["channels"] ?? "") 声道  ·  \(size(ab))  ·  \(duration)"
            log("已识别视频与音频；预计输出约 " + size(vb + ab) + "。")
        case "status":
            status.stringValue = event["message"] as? String ?? "正在处理…"
            if let cancellable = event["cancellable"] as? Bool { cancelButton.isEnabled = cancellable }
            log(status.stringValue)
        case "progress":
            let fraction = event["fraction"] as? Double ?? 0
            progress.stopAnimation(nil); progress.isIndeterminate = false
            progress.doubleValue = fraction
            let elapsed = event["elapsed"] as? Double ?? 0
            let bytes = (event["bytes"] as? NSNumber)?.int64Value ?? 0
            status.stringValue = String(format: "正在合并 · %.0f%%", fraction * 100)
            detail.stringValue = "已写入 \(size(bytes))  ·  用时 \(Int(elapsed)) 秒  ·  可以随时取消"
        case "done":
            terminalEvent = true
            progress.stopAnimation(nil); progress.isIndeterminate = false; progress.doubleValue = 1
            status.stringValue = "合并完成，音视频轨道检查通过"
            status.textColor = .labelColor
            let bytes = (event["bytes"] as? NSNumber)?.int64Value ?? 0
            let elapsed = event["elapsed"] as? Double ?? 0
            detail.stringValue = "\(size(bytes))  ·  用时 \(String(format: "%.1f", elapsed)) 秒  ·  原文件已保留"
            if let path = event["output"] as? String { resultURL = URL(fileURLWithPath: path); log("已保存：" + path) }
            revealButton.isHidden = false; playButton.isHidden = false
            startButton.title = "再次合并"
            log("输出检查通过：视频、音频、编码与时长均符合预期。")
        case "cancelled":
            terminalEvent = true
            status.stringValue = "已取消"
            detail.stringValue = event["message"] as? String ?? "源文件未改动。"
            progress.doubleValue = 0
            log(detail.stringValue)
        case "error":
            terminalEvent = true
            fail(event["message"] as? String ?? "发生未知错误。")
        default: break
        }
    }

    func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    func fail(_ message: String) {
        status.stringValue = "未能完成，请检查下方记录"
        status.textColor = .systemRed
        detail.stringValue = message.components(separatedBy: "\n").first ?? message
        progress.stopAnimation(nil); progress.isIndeterminate = false
        log(message)
    }
    @objc func cancel() {
        guard let task = process, task.isRunning else { return }
        cancelButton.isEnabled = false
        status.stringValue = "正在取消并清理临时文件…"
        task.terminate()
    }
    @objc func reveal() { if let url = resultURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    @objc func play() { if let url = resultURL { NSWorkspace.shared.open(url) } }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if busy { confirmQuit(); return false }
        NSApp.terminate(nil); return true
    }
    func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "取消当前任务并退出？"
        alert.informativeText = "临时文件会清理，原文件不会改动。"
        alert.addButton(withTitle: "继续处理")
        alert.addButton(withTitle: "取消并退出")
        alert.beginSheetModal(for: window) { answer in
            if answer == .alertSecondButtonReturn { self.closeWhenFinished = true; self.cancel() }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if busy { confirmQuit(); return .terminateCancel }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
