import Foundation

enum Frame {
    static let reportID: UInt8 = 0x13

    static func make(cmd: UInt8, sub: UInt8, seq: Int, data: [UInt8], lenByte: UInt8? = nil) -> [UInt8] {
        var f = [UInt8](repeating: 0, count: 20)
        f[0] = reportID
        f[1] = cmd
        f[2] = sub
        f[3] = UInt8(seq & 0xFF)
        let d = Array(data.prefix(14))
        f[4] = lenByte ?? UInt8(d.count)
        for (i, b) in d.enumerated() { f[5 + i] = b }
        f[19] = checksum(f)
        return f
    }

    static func checksum(_ f: [UInt8]) -> UInt8 {
        var s = 0
        for i in 0..<19 { s += Int(f[i]) }
        return UInt8(s & 0xFF)
    }

    static func reseal(_ f: inout [UInt8]) {
        f[19] = 0
        f[19] = checksum(f)
    }

    static func data(_ f: [UInt8]) -> [UInt8] {
        let n = Int(f[4] & 0x0F)
        return Array(f[5..<min(19, 5 + n)])
    }
}

@MainActor
final class KZZIController {
    let hid = HIDService()
    private var rx: [[UInt8]] = []
    private var waiters: [UUID: Waiter] = [:]
    private var lastError: String?

    private struct Waiter {
        let pred: ([UInt8]) -> Bool
        let cont: CheckedContinuation<[UInt8]?, Never>
    }

    init() {
        hid.onFrame = { [weak self] f in
            guard let self else { return }
            Task { @MainActor in self.handle(f) }
        }
    }

    func start() { hid.start() }

    private func handle(_ f: [UInt8]) {
        guard f.count >= 20, f[0] == 0x13 else { return }
        for (id, w) in waiters where w.pred(f) {
            waiters.removeValue(forKey: id)
            w.cont.resume(returning: f)
        }
        rx.append(f)
        if rx.count > 400 { rx.removeFirst(rx.count - 400) }
    }

    private func waitFor(_ pred: @escaping ([UInt8]) -> Bool, timeout: Double) async -> [UInt8]? {
        if let f = rx.first(where: pred) { rx.removeAll { $0 == f }; return f }
        return await withCheckedContinuation { cont in
            let id = UUID()
            waiters[id] = Waiter(pred: pred, cont: cont)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, let w = self.waiters.removeValue(forKey: id) else { return }
                w.cont.resume(returning: nil)
            }
        }
    }

    @discardableResult
    private func collect(cmd: UInt8, count: Int, timeout: Double, filter: @escaping ([UInt8]) -> Bool = { _ in true }) async -> [[UInt8]] {
        var out: [Int: [UInt8]] = [:]
        for f in rx where f[1] == cmd && filter(f) { out[Int(f[3])] = f }
        rx.removeAll()
        let deadline = Date().addingTimeInterval(timeout)
        while out.count < count && Date() < deadline {
            let got = await waitFor({ $0[1] == cmd && filter($0) }, timeout: 0.25)
            if let got { out[Int(got[3])] = got }
        }
        return out.keys.sorted().compactMap { out[$0] }
    }

    func ping() async -> Bool {
        rx.removeAll()
        guard hid.send(Frame.make(cmd: 0x07, sub: 1, seq: 0, data: [0])) else { return false }
        return await waitFor({ $0[1] == 0x07 }, timeout: 0.4) != nil
    }

    // MARK: config
    func readConfig() async -> [[UInt8]] {
        var got: [Int: [UInt8]] = [:]
        for _ in 0..<5 where got.count < 10 {
            _ = await ping()
            _ = hid.send(Frame.make(cmd: 0x44, sub: 1, seq: 0, data: [UInt8](repeating: 0, count: 14)))
            let frags = await collect(cmd: 0x44, count: 10, timeout: 1.0) { $0[2] == 0x0A }
            for f in frags { got[Int(f[3])] = f }
        }
        return got.keys.sorted().compactMap { got[$0] }
    }

    func writeConfig(_ frags: [[UInt8]]) async -> Int {
        guard !frags.isEmpty else { return 0 }
        _ = await ping()
        var echoed = 0
        for f0 in frags {
            var f = f0
            f[1] = 0x04
            if f[3] == 0 { f[8] = 0x01; f[14] = 0x00 }
            Frame.reseal(&f)
            rx.removeAll()
            let sent = hid.send(f)
            let got = await waitFor({ $0[1] == 0x04 && $0[3] == f[3] }, timeout: 0.6)
            if sent, got != nil { echoed += 1 }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        if echoed == 0 { lastError = "配置写入没有回包" }
        return echoed
    }

    func save() async {
        _ = await ping()
        _ = hid.send(Frame.make(cmd: 0x0A, sub: 1, seq: 0, data: [0x04, 0x07] + [UInt8](repeating: 0, count: 12)))
        try? await Task.sleep(nanoseconds: 350_000_000)
    }

    // MARK: keymap
    func readKeymap(layer: Int) async -> [UInt8]? {
        var got: [Int: [UInt8]] = [:]
        for _ in 0..<8 where got.count < 36 {
            _ = await ping()
            var req = Frame.make(cmd: 0x41, sub: 1, seq: 0, data: [UInt8](repeating: 0, count: 14))
            req[4] = UInt8((layer != 0 ? 0x10 : 0x00) | 0x0E)
            Frame.reseal(&req)
            _ = hid.send(req)
            let frags = await collect(cmd: 0x41, count: 36, timeout: 1.3)
            for f in frags { got[Int(f[3])] = f }
        }
        guard got.count >= 36 else { return nil }
        var out = [UInt8](repeating: 0, count: 504)
        for (seq, f) in got {
            let d = Frame.data(f)
            for (i, b) in d.enumerated() where seq < 36 { out[seq * 14 + i] = b }
        }
        return out
    }

    func writeKeymap(_ data: [UInt8], layer: Int) async {
        let total = (data.count + 13) / 14
        _ = await ping()
        for seq in 0..<total {
            let start = seq * 14
            let chunk = Array(data[start..<min(start + 14, data.count)])
            var f = Frame.make(cmd: 0x01, sub: UInt8(total), seq: seq, data: chunk)
            f[4] = UInt8((layer != 0 ? 0x10 : 0x00) | UInt8(chunk.count))
            Frame.reseal(&f)
            rx.removeAll()
            _ = hid.send(f)
            _ = await waitFor({ $0[1] == 0x01 && $0[3] == f[3] }, timeout: 0.5)
            try? await Task.sleep(nanoseconds: 18_000_000)
        }
    }

    // MARK: per-key
    func writePerKey(colors: [[UInt8]]) async {
        var planes = [[UInt8]](repeating: [UInt8](repeating: 0, count: 126), count: 3)
        for i in 0..<126 {
            let c = i < colors.count ? colors[i] : [0, 0, 0]
            planes[0][i] = c.count > 0 ? c[0] : 0
            planes[1][i] = c.count > 1 ? c[1] : 0
            planes[2][i] = c.count > 2 ? c[2] : 0
        }
        _ = await ping()
        for seq in 0..<27 {
            let p = seq / 9, k = seq % 9
            let start = k * 14
            let vals = Array(planes[p][start..<start + 14])
            var f = Frame.make(cmd: 0x02, sub: 0x1C, seq: seq, data: vals)
            Frame.reseal(&f)
            rx.removeAll()
            _ = hid.send(f)
            _ = await waitFor({ $0[1] == 0x02 && $0[3] == f[3] }, timeout: 0.4)
            try? await Task.sleep(nanoseconds: 12_000_000)
        }
        var trailer = Frame.make(cmd: 0x02, sub: 0x1C, seq: 27, data: [0x06, 0, 0, 0x5A, 0xA5, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        Frame.reseal(&trailer)
        _ = hid.send(trailer)
        try? await Task.sleep(nanoseconds: 60_000_000)
    }

    // MARK: macro area (read only)
    func readMacroArea() async -> [UInt8] {
        var got: [Int: [UInt8]] = [:]
        for _ in 0..<8 where got.count < 27 {
            _ = await ping()
            var req = Frame.make(cmd: 0x42, sub: 1, seq: 0, data: [0, 0, 0, 0])
            req[4] = 0x04
            Frame.reseal(&req)
            _ = hid.send(req)
            let frags = await collect(cmd: 0x42, count: 27, timeout: 0.9)
            for f in frags { got[Int(f[3])] = f }
        }
        var out: [UInt8] = []
        for seq in got.keys.sorted() {
            if let f = got[seq] { out.append(contentsOf: Frame.data(f)) }
        }
        return out
    }
}

// MARK: - Config helpers

enum CFG {
    static func effect(_ f: [[UInt8]]) -> Int { f.count > 0 ? Int(f[0][15]) : 0 }
    static func brightness(_ f: [[UInt8]]) -> Int { slotBrightness(f, effect: effect(f)) }
    static func speed(_ f: [[UInt8]]) -> Int { slotSpeed(f, effect: effect(f)) }

    static func effectSlot(_ effect: Int) -> (Int, Int)? {
        switch effect {
        case 1...6: return (4, 7 + (effect - 1) * 2)
        case 7...13: return (5, 5 + (effect - 7) * 2)
        case 14...18: return (6, 5 + (effect - 14) * 2)
        default: return (4, 7)
        }
    }

    static func slotBrightness(_ f: [[UInt8]], effect: Int) -> Int {
        guard let (s, o) = effectSlot(effect), s < f.count, o < 19 else { return 0 }
        return Int(f[s][o])
    }

    static func slotSpeed(_ f: [[UInt8]], effect: Int) -> Int {
        guard let (s, o) = effectSlot(effect), s < f.count, o + 1 < 19 else { return 0 }
        return Int((f[s][o + 1] >> 4) & 0x0F)
    }

    static func setBrightness(_ f: inout [[UInt8]], effect: Int, value: Int) {
        guard let (s, o) = effectSlot(effect), s < f.count else { return }
        f[s][o] = UInt8(max(0, min(15, value)))
    }

    static func setSpeed(_ f: inout [[UInt8]], effect: Int, value: Int) {
        guard let (s, o) = effectSlot(effect), s < f.count else { return }
        f[s][o + 1] = (UInt8((value & 0x0F) << 4)) | (f[s][o + 1] & 0x0F)
    }

    static func setEffect(_ f: inout [[UInt8]], effect: Int) {
        guard !f.isEmpty else { return }
        f[0][15] = UInt8(effect)
        f[0][8] = 0x01
        f[0][14] = 0x00
    }
}
