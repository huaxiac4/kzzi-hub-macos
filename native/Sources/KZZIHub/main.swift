import Foundation
import SwiftUI

if CommandLine.arguments.contains("--rescheck") {
    for name in ["k98_layout.json", "modes.json", "keymap.json", "k98.png"] {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let u1 = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Resources")
        let u2 = Bundle.module.url(forResource: base, withExtension: ext)
        print(name, "subdir:", u1 != nil, "root:", u2 != nil)
    }
    exit(0)
}

if CommandLine.arguments.contains("--snapshot") {
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        let m = AppModel()
        try? await Task.sleep(nanoseconds: 300_000_000)
        let view = RootView().environmentObject(m).frame(width: 1280, height: 820)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        if let img = renderer.nsImage,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/kzzi-ui.png"))
            print("snapshot written", rep.pixelsWide, "x", rep.pixelsHigh)
        } else {
            print("snapshot failed")
        }
        sem.signal()
    }
    while sem.wait(timeout: .now()) == .timedOut {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    exit(0)
}

if CommandLine.arguments.contains("--modelrun") {
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        let m = AppModel()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        print("connected:", m.connected, "layout keys:", m.layout.keys.count, "modes:", m.modes.count)
        guard m.connected else { print("NOT CONNECTED"); sem.signal(); return }
        let orig = m.effect
        print("orig effect:", orig, m.effectName)
        await m.applyEffect(3)
        try? await Task.sleep(nanoseconds: 600_000_000)
        var cfg = await m.controller.readConfig()
        print("after applyEffect(3):", CFG.effect(cfg), "config frags:", cfg.count)
        await m.applyEffect(orig)
        try? await Task.sleep(nanoseconds: 600_000_000)
        cfg = await m.controller.readConfig()
        print("restored effect:", CFG.effect(cfg))
        await m.loadKeymap(layer: 0)
        print("keymap bytes:", m.keymapL0.count, "nonzero:", m.keymapL0.filter { $0 != 0 }.count)
        sem.signal()
    }
    while sem.wait(timeout: .now()) == .timedOut {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    exit(0)
}

if CommandLine.arguments.contains("--selftest") {
    let sem = DispatchSemaphore(value: 0)
    Task { @MainActor in
        let c = KZZIController()
        c.start()
        try? await Task.sleep(nanoseconds: 900_000_000)
        print("connected:", c.hid.connected)
        print("ping:", await c.ping())
        let cfg = await c.readConfig()
        print("config frags:", cfg.count)
        if cfg.count == 10 {
            print("effect:", CFG.effect(cfg), "brightness:", CFG.brightness(cfg), "speed:", CFG.speed(cfg))
        }
        let k0 = await c.readKeymap(layer: 0) ?? []
        let k1 = await c.readKeymap(layer: 1) ?? []
        print("keymap L0 nonzero:", k0.filter { $0 != 0 }.count, "L1:", k1.filter { $0 != 0 }.count)
        sem.signal()
    }
    while sem.wait(timeout: .now()) == .timedOut {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    exit(0)
}

KZZIHubApp.main()
