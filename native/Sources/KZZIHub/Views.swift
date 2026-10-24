import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            BackgroundView()
            HStack(spacing: 16) {
                sidebar
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .buttonStyle(.glass)
            }
            .padding(18)
            .padding(.top, 8)
        }
        .frame(minWidth: 1080, minHeight: 720)
        .preferredColorScheme(.dark)
        .onChange(of: model.osMode) { v in UserDefaults.standard.set(v, forKey: "osMode") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("K").font(.system(size: 19, weight: .heavy))
                    .frame(width: 36, height: 36)
                    .background(LinearGradient(colors: [Theme.accent, Theme.accentDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("KZZI HUB").font(.system(size: 13, weight: .bold)).tracking(1.4)
                    Text("for macOS").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 16)

            VStack(spacing: 4) {
                ForEach(Tab.allCases) { t in
                    Button {
                        model.tab = t
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: t.icon).frame(width: 18)
                            Text(t.rawValue)
                            Spacer()
                        }
                        .font(.system(size: 13, weight: model.tab == t ? .semibold : .regular))
                        .padding(.vertical, 8).padding(.horizontal, 10)
                        .background {
                            if model.tab == t {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.white.opacity(0.14))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.tab == t ? .primary : .secondary)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(model.connected ? Theme.ok : Color.gray).frame(width: 8, height: 8)
                    Text(model.connected ? "已连接" : "未连接").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Circle().fill(model.accessGranted ? Theme.ok : Color.orange).frame(width: 6, height: 6)
                    Text(model.accessGranted ? "输入监控已授权" : "输入监控未授权")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .padding(14)
        .frame(width: 206)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .device: DeviceCenterView()
        case .light: LightingView()
        case .custom: CustomLightView()
        case .keys: KeysView()
        case .config: ConfigView()
        case .about: AboutView()
        }
    }
}

struct BackgroundView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let url = Bundle.module.url(forResource: "bg-stars", withExtension: "png", subdirectory: "Resources"),
                   let img = NSImage(contentsOf: url) {
                    Image(nsImage: img).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.black
                }
                LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.35)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}

enum Theme {
    static let bg = Color(red: 0.043, green: 0.05, blue: 0.067)
    static let bg2 = Color(red: 0.067, green: 0.078, blue: 0.102)
    static let card = Color(red: 0.082, green: 0.094, blue: 0.125)
    static let card2 = Color(red: 0.106, green: 0.125, blue: 0.157)
    static let line = Color.white.opacity(0.08)
    static let accent = Color(red: 1, green: 0.231, blue: 0.275)
    static let accentDark = Color(red: 0.69, green: 0.09, blue: 0.13)
    static let ok = Color(red: 0.22, green: 0.85, blue: 0.54)
}

struct Card<Content: View>: View {
    var title: String? = nil
    var hint: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 12, weight: .bold)).tracking(0.6)
                    if let hint { Text(hint).font(.system(size: 10)).foregroundStyle(.secondary) }
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct KeyboardView: View {
    let layout: LayoutFile
    var fill: (KeyDef) -> Color? = { _ in nil }
    var label: (KeyDef) -> String = { $0.label }
    var selectedLi: Int? = nil
    var onTap: ((KeyDef) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / layout.meta.width
            let sy = geo.size.height / layout.meta.height
            ZStack(alignment: .topLeading) {
                ForEach(layout.keys) { k in
                    let c = fill(k)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(c ?? Theme.card2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(selectedLi == k.li ? Theme.accent : Color.white.opacity(0.10),
                                        lineWidth: selectedLi == k.li ? 2 : 1)
                        )
                        .overlay(
                            Text(label(k))
                                .font(.system(size: min(10, max(5, k.w * sx * 0.20)), weight: .medium))
                                .foregroundStyle(c == nil ? Color.secondary : Color.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .padding(1)
                        )
                        .frame(width: max(2, k.w * sx), height: max(2, k.h * sy))
                        .position(x: (k.x + k.w / 2) * sx, y: (k.y + k.h / 2) * sy)
                        .onTapGesture { onTap?(k) }
                }
            }
        }
        .aspectRatio(layout.meta.width / layout.meta.height, contentMode: .fit)
    }
}

struct DeviceCenterView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    VStack(spacing: 0) {
                        if let url = Bundle.module.url(forResource: "k98", withExtension: "png", subdirectory: "Resources"),
                           let img = NSImage(contentsOf: url) {
                            Image(nsImage: img).resizable().scaledToFit().frame(height: 230)
                        } else {
                            Rectangle().fill(Theme.bg).frame(height: 230)
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("KZZI K98").font(.system(size: 18, weight: .heavy))
                                Text(model.connected ? "已连接 · 2.4G Wireless Receiver" : "未连接 · 2.4G Wireless Receiver")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("读取配置") { Task { await model.refreshConfig() } }
                            Button("保存到键盘") { Task { await model.saveToDevice() } }
                                .buttonStyle(.glassProminent).tint(Theme.accent)
                        }
                        .padding(.top, 12)
                    }
                }
                if !model.connected {
                    Card(title: "需要输入监控权限") {
                        HStack(spacing: 12) {
                            Text("如果没有自动连上键盘，请在「系统设置 → 隐私与安全性 → 输入监控」里勾选 KZZI HUB，然后回到这里点「重试连接」。")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                            Button("打开系统设置") {
                                if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                                    NSWorkspace.shared.open(u)
                                }
                            }
                            Button("重试连接") { Task { await model.reconnect() } }
                                .buttonStyle(.glassProminent).tint(Theme.accent)
                        }
                    }
                }
                HStack(spacing: 16) {
                    infoCard("连接", rows: [("状态", model.connected ? "已连接" : "未连接"), ("设备", "3554:FA09"), ("通道", "2.4G · IOKit HID")])
                    infoCard("当前灯效", rows: [("效果", model.connected ? model.effectName : "—"), ("亮度", model.connected ? "\(model.brightness)" : "—"), ("速度", model.connected ? "\(model.speed)" : "—")])
                    infoCard("系统", rows: [("键位模式", model.osMode == "mac" ? "macOS" : "Windows"), ("配置档", "\(profiles().count)"), ("版本", "1.0.0")])
                }
                Card(title: "日志") {
                    ScrollView {
                        Text(model.logText.isEmpty ? "—" : model.logText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 120)
                }
            }
            .padding(22)
        }
    }

    func profiles() -> [String] {
        (UserDefaults.standard.dictionary(forKey: "kzzi.profiles") as? [String: String]).map { Array($0.keys) } ?? []
    }

    func infoCard(_ title: String, rows: [(String, String)]) -> some View {
        Card(title: title) {
            VStack(spacing: 6) {
                ForEach(rows, id: \.0) { r in
                    HStack {
                        Text(r.0).foregroundStyle(.secondary)
                        Spacer()
                        Text(r.1).fontWeight(.semibold)
                    }.font(.system(size: 12))
                }
            }
        }
    }
}

struct LightingView: View {
    @EnvironmentObject var model: AppModel
    @State private var color: Color = Color(red: 1, green: 0.18, blue: 0.25)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card(title: "灯效", hint: "点击即时下发（不写 flash）") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(model.modes) { m in
                            Button {
                                Task { await model.applyEffect(m.mode) }
                            } label: {
                                Text(m.desc)
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(model.effect == m.mode ? Theme.accent.opacity(0.25) : Theme.card2)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.effect == m.mode ? Theme.accent : Color.clear))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 16) {
                    Card(title: "亮度", hint: "\(model.brightness)") {
                        Slider(value: Binding(get: { Double(model.brightness) }, set: { model.brightness = Int($0) }), in: 0...5, step: 1) { editing in
                            if !editing { Task { await model.setBrightness(model.brightness) } }
                        }
                    }
                    Card(title: "速度", hint: "\(model.speed)") {
                        Slider(value: Binding(get: { Double(model.speed) }, set: { model.speed = Int($0) }), in: 0...5, step: 1) { editing in
                            if !editing { Task { await model.setSpeed(model.speed) } }
                        }
                    }
                    Card(title: "颜色") {
                        HStack {
                            ColorPicker("", selection: $color).labelsHidden()
                            Button("应用单色") {
                                model.fillAll(rgb(color))
                                Task { await model.applyCustomColors() }
                            }
                            Button("彩虹") {
                                for i in 0..<126 {
                                    let h = Double(i) * 137.5 / 360.0
                                    model.colors[i] = hsl(h, 0.85, 0.55)
                                }
                                Task { await model.applyCustomColors() }
                            }
                        }
                    }
                }
                Card(title: "预览", hint: "当前系统：\(model.osMode == "mac" ? "macOS" : "Windows")") {
                    KeyboardView(layout: model.layout,
                                 fill: { k in previewColor(k) },
                                 label: { k in model.entry(li: k.li).map { model.shortColorFor($0) } ?? k.label })
                        .frame(height: 250)
                }
            }
            .padding(22)
        }
    }

    func previewColor(_ k: KeyDef) -> Color? {
        if model.effect == 19, let c = model.colors[k.li] {
            return Color(red: Double(c[0]) / 255, green: Double(c[1]) / 255, blue: Double(c[2]) / 255)
        }
        return nil
    }

    func rgb(_ c: Color) -> [UInt8] {
        let ns = NSColor(c).usingColorSpace(.deviceRGB) ?? NSColor.red
        return [UInt8(ns.redComponent * 255), UInt8(ns.greenComponent * 255), UInt8(ns.blueComponent * 255)]
    }

    func hsl(_ h: Double, _ s: Double, _ l: Double) -> [UInt8] {
        let f = { (n: Double) -> UInt8 in
            let k = (n + h * 12).truncatingRemainder(dividingBy: 12)
            let a = s * min(l, 1 - l)
            let v = l - a * max(-1, min(k - 3, min(9 - k, 1)))
            return UInt8(max(0, min(255, v * 255)))
        }
        return [f(0), f(8), f(4)]
    }
}

struct CustomLightView: View {
    @EnvironmentObject var model: AppModel
    @State private var brush: Color = Color(red: 1, green: 0.18, blue: 0.25)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card(title: "逐键调色", hint: "点击按键上色，然后应用到键盘") {
                    HStack {
                        ColorPicker("", selection: $brush).labelsHidden()
                        Button("全部填色") { model.fillAll(rgb(brush)) }
                        Button("彩虹填充") {
                            for i in 0..<126 {
                                let h = Double(i) * 137.5 / 360.0
                                model.colors[i] = hsl(h, 0.85, 0.55)
                            }
                        }
                        Button("全部熄灭") { model.colors.removeAll() }
                        Spacer()
                        Button("应用到键盘") { Task { await model.applyCustomColors() } }
                            .buttonStyle(.glassProminent).tint(Theme.accent)
                    }
                    KeyboardView(layout: model.layout,
                                 fill: { k in
                                     guard let c = model.colors[k.li] else { return nil }
                                     return Color(red: Double(c[0]) / 255, green: Double(c[1]) / 255, blue: Double(c[2]) / 255)
                                 },
                                 label: { k in model.entry(li: k.li).map { model.shortColorFor($0) } ?? k.label },
                                 onTap: { k in model.colors[k.li] = rgb(brush) })
                        .frame(height: 300)
                }
            }
            .padding(22)
        }
    }

    func rgb(_ c: Color) -> [UInt8] {
        let ns = NSColor(c).usingColorSpace(.deviceRGB) ?? NSColor.red
        return [UInt8(ns.redComponent * 255), UInt8(ns.greenComponent * 255), UInt8(ns.blueComponent * 255)]
    }
    func hsl(_ h: Double, _ s: Double, _ l: Double) -> [UInt8] {
        let f = { (n: Double) -> UInt8 in
            let k = (n + h * 12).truncatingRemainder(dividingBy: 12)
            let a = s * min(l, 1 - l)
            let v = l - a * max(-1, min(k - 3, min(9 - k, 1)))
            return UInt8(max(0, min(255, v * 255)))
        }
        return [f(0), f(8), f(4)]
    }
}

struct KeysView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""

    var filteredKeys: [KeyMapEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.keymap }
        return model.keymap.filter {
            $0.label.lowercased().contains(q) || $0.win.lowercased().contains(q) ||
            $0.mac.lowercased().contains(q) || $0.fn.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card(title: "按键功能对照", hint: "键盘背面的 Win/Mac 拨杆决定实际输出") {
                    HStack {
                        Picker("", selection: $model.osMode) {
                            Text("Windows").tag("win")
                            Text("macOS").tag("mac")
                        }.pickerStyle(.segmented).frame(width: 220)
                        TextField("搜索按键 / 功能", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
                        Spacer()
                    }
                    ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], spacing: 8) {
                        ForEach(filteredKeys) { e in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(e.label).fontWeight(.bold)
                                    Text(e.code).font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                                Text("Windows: \(e.win)").font(.system(size: 11)).foregroundStyle(.secondary)
                                Text("macOS: \(e.mac)").font(.system(size: 11)).foregroundStyle(.secondary)
                                if !e.fn.isEmpty { Text("Fn + \(e.label) → \(e.fn)").font(.system(size: 10)).foregroundStyle(Theme.accent) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Theme.card2)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    }
                    .frame(height: 230)
                }
                Card(title: "改键", hint: "选择键位 → 选择新功能 → 应用") {
                    HStack {
                        Picker("", selection: $model.layer) {
                            Text("主层").tag(0)
                            Text("Fn 层").tag(1)
                        }.pickerStyle(.segmented).frame(width: 160)
                        Button("读取键位表") { Task { await model.loadKeymap(layer: model.layer) } }
                        Spacer()
                        if model.layer == 0 {
                            Picker("", selection: $model.remapCode) {
                                ForEach(HID_GROUPS, id: \.0) { group in
                                    Section(group.0) {
                                        ForEach(group.1, id: \.0) { item in
                                            Text(item.1).tag(item.0)
                                        }
                                    }
                                }
                            }.frame(width: 180)
                        } else {
                            Picker("", selection: $model.fnSourceLi) {
                                Text("选择来源").tag(-1)
                                ForEach(model.keymap.filter { k in
                                    model.keymapL1.count == 504 && model.keymapL1[k.li*4..<k.li*4+4].contains { $0 != 0 }
                                }) { k in
                                    Text(k.label).tag(k.li)
                                }
                            }.frame(width: 180)
                        }
                        Button("应用改键") { Task { await model.applyRemap() } }
                            .buttonStyle(.glassProminent).tint(Theme.accent)
                        Button("恢复出厂键位") {
                            Task { await model.restoreDefaultKeymap() }
                        }
                    }
                    Text(model.remapLi >= 0 ? "已选：\(model.entry(li: model.remapLi)?.label ?? "#\(model.remapLi)")" : "在下方键盘图上点选要改的键")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    KeyboardView(layout: model.layout,
                                 label: { k in model.entry(li: k.li).map { model.shortColorFor($0) } ?? k.label },
                                 selectedLi: model.remapLi,
                                 onTap: { k in model.remapLi = k.li })
                        .frame(height: 220)
                }
            }
            .padding(22)
        }
    }
}

struct ConfigView: View {
    @EnvironmentObject var model: AppModel
    @State private var profileName = ""
    @State private var profiles: [String] = []
    @State private var status = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card(title: "键盘配置", hint: "10 包数据") {
                    HStack {
                        Button("重新读取") { Task { await model.refreshConfig() } }
                        Button("读取宏区") { Task { await model.readMacroArea() } }
                        Button("导出完整备份") { exportBackup() }
                        Button("从备份恢复") { importBackup() }
                        Spacer()
                    }
                    Text(model.config.isEmpty ? "未读取" : model.config.enumerated().map { "#\($0.offset)  \(model.hexString($0.element))" }.joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Theme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Card(title: "配置档") {
                    HStack {
                        TextField("配置档名称", text: $profileName).textFieldStyle(.roundedBorder).frame(width: 200)
                        Button("保存当前") { saveProfile() }
                        Spacer()
                    }
                    ForEach(profiles, id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button("载入") { loadProfile(name) }
                            Button("删除") { deleteProfile(name) }
                        }
                        .font(.system(size: 12))
                        .padding(.vertical, 3)
                    }
                    if profiles.isEmpty { Text("还没有配置档").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Card(title: "宏区（只读）") {
                    ScrollView {
                        Text(model.macroHex).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 100)
                }
                Card(title: "日志") {
                    ScrollView {
                        Text(model.logText.isEmpty ? "—" : model.logText)
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 140)
                }
            }
            .padding(22)
        }
        .onAppear { profiles = loadProfileNames() }
    }

    func loadProfileNames() -> [String] {
        ((UserDefaults.standard.dictionary(forKey: "kzzi.profiles") as? [String: String]) ?? [:]).keys.sorted()
    }

    func saveProfile() {
        let name = profileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, model.config.count == 10 else { return }
        var all = (UserDefaults.standard.dictionary(forKey: "kzzi.profiles") as? [String: String]) ?? [:]
        var obj: [String: Any] = [:]
        obj["config"] = model.config.map { model.hexString($0) }
        obj["keymap"] = model.hexString(model.keymapL0)
        obj["fnlayer"] = model.hexString(model.keymapL1)
        if let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) {
            all[name] = s
            UserDefaults.standard.set(all, forKey: "kzzi.profiles")
            profiles = all.keys.sorted()
            profileName = ""
        }
    }

    func loadProfile(_ name: String) {
        guard let all = UserDefaults.standard.dictionary(forKey: "kzzi.profiles") as? [String: String],
              let s = all[name], let d = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        Task { await restore(obj: obj) }
    }

    func deleteProfile(_ name: String) {
        var all = (UserDefaults.standard.dictionary(forKey: "kzzi.profiles") as? [String: String]) ?? [:]
        all.removeValue(forKey: name)
        UserDefaults.standard.set(all, forKey: "kzzi.profiles")
        profiles = all.keys.sorted()
    }

    func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "kzzi-k98-backup.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var obj: [String: Any] = ["app": "kzzi-hub-mac", "version": 2]
        obj["config"] = model.config.map { model.hexString($0) }
        obj["keymap"] = model.hexString(model.keymapL0)
        obj["fnlayer"] = model.hexString(model.keymapL1)
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
            try? d.write(to: url)
            model.appendLog("已导出备份：\(url.lastPathComponent)")
        }
    }

    func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let d = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        Task { await restore(obj: obj) }
    }

    func restore(obj: [String: Any]) async {
        guard let cfgHex = obj["config"] as? [String] else { return }
        var frags: [[UInt8]] = []
        for h in cfgHex {
            let bytes = h.split(separator: " ").compactMap { UInt8($0, radix: 16) }
            if bytes.count == 20 { frags.append(bytes) }
        }
        guard frags.count == 10 else { model.appendLog("备份文件里的配置不完整"); return }
        await model.controller.writeConfig(frags)
        if let km = obj["keymap"] as? String {
            let bytes = km.split(separator: " ").compactMap { UInt8($0, radix: 16) }
            if bytes.count == 504 { await model.controller.writeKeymap(bytes, layer: 0); model.keymapL0 = bytes }
        }
        if let fn = obj["fnlayer"] as? String {
            let bytes = fn.split(separator: " ").compactMap { UInt8($0, radix: 16) }
            if bytes.count == 504 { await model.controller.writeKeymap(bytes, layer: 1); model.keymapL1 = bytes }
        }
        await model.controller.save()
        model.config = frags
        model.effect = CFG.effect(frags)
        model.brightness = CFG.brightness(frags)
        model.speed = CFG.speed(frags)
        model.appendLog("已从备份恢复配置 + 键位")
    }
}

struct AboutView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("KZZI HUB for macOS").font(.system(size: 22, weight: .heavy))
                Text("原生 macOS 版 KZZI K98 驱动，直接通过 IOKit HID 与 2.4G 接收器（3554:FA09，usage page 0xFF02）通讯，不依赖浏览器或内核扩展。")
                    .font(.system(size: 13))
                Text("功能：17 种灯效 / 亮度 / 速度 / 单色 / 逐键 RGB / 保存到键盘 / 主层与 Fn 层改键 / Win-Mac 键位对照 / 配置档 / 完整备份恢复。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text("协议来自官方 KZZI Hub 1.0.4.1 的逆向（KBAccess.dll / DeviceDriver.exe）。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Divider().padding(.vertical, 6)
                HStack(spacing: 24) {
                    Label("输入监控：\(model.accessGranted ? "已授权" : "未授权")", systemImage: model.accessGranted ? "checkmark.circle" : "exclamationmark.triangle")
                    Label("设备：\(model.connected ? "已连接" : "未连接")", systemImage: "cable.connector")
                    Label("灯效数：\(model.modes.count)", systemImage: "lightbulb")
                    Label("键位：\(model.layout.keys.count)", systemImage: "keyboard")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
