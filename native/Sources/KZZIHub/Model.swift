import Foundation
import SwiftUI
import AppKit
import os

struct Meta: Codable { let width: Double; let height: Double }
struct KeyDef: Codable, Identifiable {
    var id: Int { li }
    let code: String
    let label: String
    let li: Int
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}
struct LayoutFile: Codable { let meta: Meta; let keys: [KeyDef] }
struct ModeDef: Codable, Identifiable {
    var id: Int { mode }
    let name: String
    let desc: String
    let mode: Int
    let attr: Int
}
struct KeyMapEntry: Codable, Identifiable {
    var id: Int { li }
    let code: String
    let label: String
    let li: Int
    let win: String
    let mac: String
    let fn: String
}

enum Tab: String, CaseIterable, Identifiable {
    case device = "设备中心"
    case light = "灯光"
    case custom = "自定义灯光"
    case keys = "按键功能"
    case config = "配置"
    case about = "关于"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .device: return "keyboard"
        case .light: return "lightbulb"
        case .custom: return "paintpalette"
        case .keys: return "command"
        case .config: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct HIDOption: Identifiable {
    let group: String
    let code: Int
    let name: String
    var id: Int { code }
}

let HID_GROUPS: [(String, [(Int, String)])] = [
    ("功能键", [(0x29,"Esc"),(0x3A,"F1"),(0x3B,"F2"),(0x3C,"F3"),(0x3D,"F4"),(0x3E,"F5"),(0x3F,"F6"),(0x40,"F7"),(0x41,"F8"),(0x42,"F9"),(0x43,"F10"),(0x44,"F11"),(0x45,"F12")]),
    ("主键区", [(0x35,"` ~"),(0x1E,"1"),(0x1F,"2"),(0x20,"3"),(0x21,"4"),(0x22,"5"),(0x23,"6"),(0x24,"7"),(0x25,"8"),(0x26,"9"),(0x27,"0"),(0x2D,"- _"),(0x2E,"= +"),(0x2A,"Backspace"),(0x2B,"Tab"),(0x2F,"[ {"),(0x30,"] }"),(0x31,"\\ |"),(0x39,"Caps Lock"),(0x33,"; :"),(0x34,"' \""),(0x28,"Enter"),(0x36,", <"),(0x37,". >"),(0x38,"/ ?"),(0x2C,"Space")]),
    ("字母", (0..<26).map { (0x04 + $0, String(UnicodeScalar(65 + $0)!)) }),
    ("导航", [(0x49,"Insert"),(0x4A,"Home"),(0x4B,"Page Up"),(0x4C,"Delete"),(0x4D,"End"),(0x4E,"Page Down"),(0x4F,"Right"),(0x50,"Left"),(0x51,"Down"),(0x52,"Up"),(0x46,"Print Screen"),(0x47,"Scroll Lock"),(0x48,"Pause"),(0x53,"Num Lock")]),
    ("修饰键", [(0xE0,"LCtrl"),(0xE1,"LShift"),(0xE2,"LAlt"),(0xE3,"LGUI/Win"),(0xE4,"RCtrl"),(0xE5,"RShift"),(0xE6,"RAlt"),(0xE7,"RGUI/Win")]),
    ("禁用", [(0,"无 / 不发送")]),
]

@MainActor
final class AppModel: ObservableObject {
    @Published var tab: Tab = .device
    @Published var connected = false
    @Published var config: [[UInt8]] = []
    @Published var effect = 2
    @Published var brightness = 5
    @Published var speed = 5
    @Published var osMode = UserDefaults.standard.string(forKey: "osMode") ?? "mac"
    @Published var logText = ""
    @Published var busy = false
    @Published var status: String = ""
    @Published var keymapL0: [UInt8] = []
    @Published var keymapL1: [UInt8] = []
    @Published var keymapValid = false
    @Published var layer = 0
    @Published var remapLi: Int = -1
    @Published var remapCode: Int = 0
    @Published var fnSourceLi: Int = -1
    @Published var macroHex: String = "未读取"
    @Published var colors: [Int: [UInt8]] = [:]
    @Published var brush: Color = Color(red: 1, green: 0.18, blue: 0.25)
    @Published var showPermissionAlert = false
    @Published var accessGranted = true

    let controller = KZZIController()
    var layout: LayoutFile = LayoutFile(meta: Meta(width: 980, height: 350), keys: [])
    var modes: [ModeDef] = []
    var keymap: [KeyMapEntry] = []

    init() {
        loadResources()
        controller.hid.onConnectionChange = { [weak self] up in
            guard let self else { return }
            Task { @MainActor in
                self.connected = up
                self.appendLog(up ? "已连接键盘" : "设备已断开")
                if up { await self.refreshConfig(auto: true) }
            }
        }
        let tabMap: [String: Tab] = ["device": .device, "light": .light, "custom": .custom,
                                     "keys": .keys, "config": .config, "about": .about]
        if let i = CommandLine.arguments.firstIndex(of: "--tab"), i + 1 < CommandLine.arguments.count,
           let t = tabMap[CommandLine.arguments[i + 1]] { tab = t }
        if let s = UserDefaults.standard.string(forKey: "startTab"), let t = tabMap[s] { tab = t }
        controller.start()
        accessGranted = controller.hid.accessGranted
        accessGranted = controller.hid.accessGranted
        showPermissionAlert = !controller.hid.accessGranted && !UserDefaults.standard.bool(forKey: "suppressPermissionAlert")
    }

    func loadResources() {
        if let url = Bundle.module.url(forResource: "k98_layout", withExtension: "json", subdirectory: "Resources"),
           let data = try? Data(contentsOf: url),
           let f = try? JSONDecoder().decode(LayoutFile.self, from: data) { layout = f }
        if let url = Bundle.module.url(forResource: "modes", withExtension: "json", subdirectory: "Resources"),
           let data = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode([ModeDef].self, from: data) { modes = m }
        if let url = Bundle.module.url(forResource: "keymap", withExtension: "json", subdirectory: "Resources"),
           let data = try? Data(contentsOf: url),
           let k = try? JSONDecoder().decode([KeyMapEntry].self, from: data) { keymap = k }
    }

    private let logger = Logger(subsystem: "com.kzzi.hub", category: "app")

    func reconnect() async {
        appendLog("重新尝试连接…")
        controller.hid.stop()
        try? await Task.sleep(nanoseconds: 400_000_000)
        controller.hid.start()
        accessGranted = controller.hid.accessGranted
        showPermissionAlert = !controller.hid.accessGranted && !UserDefaults.standard.bool(forKey: "suppressPermissionAlert")
        if controller.hid.accessGranted { appendLog("已获得输入监控权限") }
    }

    func appendLog(_ s: String) {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        logText += "[\(df.string(from: Date()))] \(s)\n"
        logger.info("\(s, privacy: .public)")
        let line = "[\(df.string(from: Date()))] \(s)\n"
        if let d = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/kzzi-native.log")
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(d); try? h.close()
            } else {
                try? d.write(to: url)
            }
        }
    }

    var effectName: String {
        if effect == 19 { return "自定义" }
        return modes.first(where: { $0.mode == effect })?.desc ?? "模式 \(effect)"
    }

    func colorFor(_ entry: KeyMapEntry) -> String {
        osMode == "mac" ? entry.mac : entry.win
    }

    func shortColorFor(_ entry: KeyMapEntry) -> String {
        let name = colorFor(entry)
        let map: [String: String] = ["⌃ Control":"⌃","⇧ Shift":"⇧","⌥ Option":"⌥","⌘ Command":"⌘",
            "⌫ Delete":"⌫","⌦ Forward Delete":"⌦","↩ Return":"↩","⌤ Enter":"⌤","⇪ Caps Lock":"⇪",
            "Num Lock":"Clear","Delete":"Del","Backspace":"Bksp","Num Enter":"↵","Menu":"Menu",
            "Print Screen":"PrtSc","⇞ Page Up":"PgUp","⇟ Page Down":"PgDn","↖ Home":"Home","↘ End":"End",
            "Context Menu":"Menu","Enter":"↩"]
        return map[name] ?? name
    }

    func entry(li: Int) -> KeyMapEntry? { keymap.first(where: { $0.li == li }) }

    // MARK: actions
    func refreshConfig(auto: Bool = false) async {
        busy = true; defer { busy = false }
        let frags = await controller.readConfig()
        guard frags.count == 10 else { appendLog("读取配置失败（\(frags.count)/10）"); return }
        config = frags
        effect = CFG.effect(frags)
        brightness = CFG.brightness(frags)
        speed = CFG.speed(frags)
        appendLog("配置已读取：\(effectName) 亮度 \(brightness) 速度 \(speed)")
        if effect == 100 {
            appendLog("检测到已移除的音乐律动模式，自动切回呼吸灯")
            var f = config
            CFG.setEffect(&f, effect: 2)
            await controller.writeConfig(f)
            config = f; effect = 2
        }
    }

    func applyEffect(_ mode: Int) async {
        guard config.count == 10 else { return }
        var f = config
        CFG.setEffect(&f, effect: mode)
        f[0][6] = UInt8(brightness)
        CFG.setBrightness(&f, effect: mode, value: brightness)
        CFG.setSpeed(&f, effect: mode, value: speed)
        await controller.writeConfig(f)
        config = f; effect = mode
        appendLog("切换灯效：\(effectName)")
    }

    func setBrightness(_ v: Int) async {
        guard config.count == 10 else { return }
        brightness = v
        var f = config
        f[0][6] = UInt8(v)
        CFG.setBrightness(&f, effect: effect, value: v)
        await controller.writeConfig(f)
        config = f
    }

    func setSpeed(_ v: Int) async {
        guard config.count == 10 else { return }
        speed = v
        var f = config
        CFG.setSpeed(&f, effect: effect, value: v)
        await controller.writeConfig(f)
        config = f
    }

    func fillAll(_ rgb: [UInt8]) {
        for i in 0..<126 { colors[i] = rgb }
    }

    func applyCustomColors() async {
        guard config.count == 10 else { return }
        busy = true; defer { busy = false }
        var f = config
        CFG.setEffect(&f, effect: 19)
        f[0][17] = 0x01
        CFG.setBrightness(&f, effect: 19, value: brightness)
        CFG.setSpeed(&f, effect: 19, value: speed)
        await controller.writeConfig(f)
        var arr = [[UInt8]](repeating: [0,0,0], count: 126)
        for (i, c) in colors where i >= 0 && i < 126 { arr[i] = c }
        await controller.writePerKey(colors: arr)
        config = f; effect = 19
        appendLog("逐键颜色已应用（\(colors.count) 个键）")
    }

    func saveToDevice() async {
        busy = true; defer { busy = false }
        await controller.save()
        appendLog("已保存到键盘 flash")
        status = "已保存"
    }

    func loadKeymap(layer: Int) async {
        busy = true; defer { busy = false }
        guard let d = await controller.readKeymap(layer: layer), d.count == 504 else {
            keymapValid = false
            appendLog("键位表读取不完整，已放弃（不会写入键盘）")
            status = "读取失败，请重试"
            return
        }
        if layer == 0 { keymapL0 = d; keymapValid = true } else { keymapL1 = d }
        appendLog(layer == 0 ? "主层键位表已读取" : "Fn 层键位表已读取")
    }

    func applyRemap() async {
        guard remapLi >= 0 else { status = "请先选择键位"; return }
        if layer == 0 && !keymapValid { status = "请先完整读取键位表"; return }
        var data = layer == 0 ? keymapL0 : keymapL1
        guard data.count == 504 else { status = "键位表未读取"; return }
        let backup = data
        let idx = remapLi * 4
        if layer == 1 {
            guard fnSourceLi >= 0 else { status = "请选择来源 Fn 功能"; return }
            guard data.count >= idx + 4, layer == 1 else { return }
            let src = fnSourceLi * 4
            if src + 4 <= data.count { data.replaceSubrange(idx..<idx+4, with: data[src..<src+4]) }
        } else {
            data[idx] = 0; data[idx+2] = 0
            if remapCode >= 0xE0 && remapCode <= 0xE7 {
                data[idx+1] = UInt8(1 << (remapCode - 0xE0)); data[idx+3] = 0
            } else {
                data[idx+1] = 0; data[idx+3] = UInt8(remapCode & 0xFF)
            }
        }
        busy = true; defer { busy = false }
        await controller.writeKeymap(data, layer: layer)
        await controller.save()
        // read back and verify; roll back on mismatch
        let check = await controller.readKeymap(layer: layer)
        if let check, check == data {
            if layer == 0 { keymapL0 = data } else { keymapL1 = data }
            appendLog("改键已写入并保存（\(layer == 0 ? "主层" : "Fn 层")）")
            status = "改键完成"
        } else {
            appendLog("改键校验失败，正在回滚…")
            await controller.writeKeymap(backup, layer: layer)
            await controller.save()
            if layer == 0 { keymapL0 = backup } else { keymapL1 = backup }
            status = "改键失败，已回滚"
        }
    }

    func restoreDefaultKeymap() async {
        guard let url = Bundle.module.url(forResource: "keymap_default", withExtension: "json", subdirectory: "Resources"),
              let text = try? String(contentsOf: url),
              let data = Self.bytes(fromHex: text), data.count == 504 else {
            status = "缺少默认键位数据"; return
        }
        busy = true; defer { busy = false }
        await controller.writeKeymap(data, layer: 0)
        await controller.save()
        keymapL0 = data; keymapValid = true
        appendLog("已恢复默认主层键位")
        status = "已恢复默认键位"
    }

    static func bytes(fromHex s: String) -> [UInt8]? {
        let parts = s.split(whereSeparator: { $0 == " " || $0 == "\n" })
        var out: [UInt8] = []
        for p in parts { guard let b = UInt8(p, radix: 16) else { return nil }; out.append(b) }
        return out
    }

    func backupJSON() -> String {
        let cfg = config.map { $0.map { String(format: "%02x", $0) }.joined(separator: " ") }
        return """
        {"app":"kzzi-hub-mac","version":2,"config":\(jsonArray(cfg)),"keymap":"\(hexString(keymapL0))","fnlayer":"\(hexString(keymapL1))"}
        """
    }

    func readMacroArea() async {
        busy = true; defer { busy = false }
        let d = await controller.readMacroArea()
        macroHex = d.isEmpty ? "没有读到数据" : "\(d.count) 字节\n" + hexString(d)
    }

    func hexString(_ d: [UInt8]) -> String { d.map { String(format: "%02x", $0) }.joined(separator: " ") }

    func jsonArray(_ arr: [String]) -> String {
        "[" + arr.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }
}
