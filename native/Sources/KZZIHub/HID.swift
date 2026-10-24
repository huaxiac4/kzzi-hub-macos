import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

func hidDebug(_ msg: String) {
    let line = msg + "\n"
    if let d = line.data(using: .utf8) {
        let url = URL(fileURLWithPath: "/tmp/kzzi-hid.log")
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(d); try? h.close() }
        else { try? d.write(to: url) }
    }
}

/// Direct IOKit HID access to the KZZI 2.4G receiver vendor collection.
final class HIDService {
    static let vendorID = 0x3554
    static let productID = 0xFA09
    static let vendorUsagePage = 0xFF02

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private let bufferSize = 4096

    var onConnectionChange: ((Bool) -> Void)?
    var onFrame: (([UInt8]) -> Void)?

    private(set) var connected = false
    private(set) var accessGranted = true

    static func ensureInputAccess() -> Bool {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let msg = "IOHID access(raw=\(access.rawValue))\n"
        if let d = msg.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/kzzi-access.log")
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(d); try? h.close() }
            else { try? d.write(to: url) }
        }
        if access == kIOHIDAccessTypeGranted { return true }
        return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    func start() {
        if manager != nil { return }
        accessGranted = HIDService.ensureInputAccess()
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID
        ] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { context, _, _, dev in
            guard let context else { return }
            Unmanaged<HIDService>.fromOpaque(context).takeUnretainedValue().attach(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { context, _, _, dev in
            guard let context else { return }
            Unmanaged<HIDService>.fromOpaque(context).takeUnretainedValue().detach(dev)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
    }

    func stop() {
        if let d = device {
            IOHIDDeviceUnscheduleFromRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let b = inputBuffer { b.deallocate(); inputBuffer = nil }
        device = nil
        if let m = manager {
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        if connected { connected = false; DispatchQueue.main.async { self.onConnectionChange?(false) } }
    }

    private func propInt(_ d: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue ?? -1
    }

    private func attach(_ dev: IOHIDDevice) {
        let up = propInt(dev, kIOHIDPrimaryUsagePageKey)
        hidDebug("attach usagePage=0x\(String(up, radix: 16))")
        guard up == Self.vendorUsagePage else { return }
        if connected { return }
        let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        hidDebug("open -> 0x\(String(r, radix: 16))")
        guard r == kIOReturnSuccess else { return }
        device = dev
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        inputBuffer = buf
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, buf, bufferSize, { context, _, _, _, rid, report, length in
            guard let context else { return }
            let svc = Unmanaged<HIDService>.fromOpaque(context).takeUnretainedValue()
            var frame = [UInt8](repeating: 0, count: max(0, length))
            for i in 0..<max(0, length) { frame[i] = report[i] }
            if frame.first != 0x13 { frame.insert(UInt8(rid & 0xff), at: 0) }
            DispatchQueue.main.async { svc.onFrame?(frame) }
        }, ctx)
        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        connected = true
        DispatchQueue.main.async { self.onConnectionChange?(true) }
    }

    private func detach(_ dev: IOHIDDevice) {
        guard let d = device, d === dev else { return }
        IOHIDDeviceUnscheduleFromRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone))
        if let b = inputBuffer { b.deallocate(); inputBuffer = nil }
        device = nil
        connected = false
        DispatchQueue.main.async { self.onConnectionChange?(false) }
    }

    /// Sends a full 20-byte frame (report id included).
    @discardableResult
    func send(_ frame: [UInt8]) -> Bool {
        guard let d = device, frame.count == 20 else { return false }
        var f = frame
        let res = f.withUnsafeMutableBufferPointer { p -> IOReturn in
            IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, CFIndex(frame[0]), p.baseAddress!, p.count)
        }
        return res == kIOReturnSuccess
    }
}
