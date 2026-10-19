import Foundation
import IOKit
import IOKit.hid
import CoreFoundation

// MARK: - Discovery (no device open, safe to poll)

public enum VIADiscovery {
    /// Find every HID device that exposes the VIA Raw HID collection (0xFF60/0x61).
    public static func find() -> [VIADevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        var result: [VIADevice] = []
        for device in deviceSet {
            if let info = describe(device) {
                result.append(info)
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.vendorID != rhs.vendorID { return lhs.vendorID < rhs.vendorID }
            if lhs.productID != rhs.productID { return lhs.productID < rhs.productID }
            return lhs.locationID < rhs.locationID
        }
    }

    static func describe(_ device: IOHIDDevice) -> VIADevice? {
        guard intProperty(device, kIOHIDPrimaryUsagePageKey) == AppConstants.rawUsagePage,
              intProperty(device, kIOHIDPrimaryUsageKey) == AppConstants.rawUsage else {
            return nil
        }
        let product = stringProperty(device, kIOHIDProductKey) ?? "VIA Keyboard"
        let transport = stringProperty(device, kIOHIDTransportKey) ?? "USB"
        return VIADevice(
            product: product,
            vendorID: intProperty(device, kIOHIDVendorIDKey) ?? 0,
            productID: intProperty(device, kIOHIDProductIDKey) ?? 0,
            locationID: intProperty(device, kIOHIDLocationIDKey) ?? 0,
            transport: transport
        )
    }

    static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        if CFGetTypeID(value) == CFNumberGetTypeID() {
            return (value as? NSNumber)?.intValue
        }
        return nil
    }

    static func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        if CFGetTypeID(value) == CFStringGetTypeID() {
            return value as? String
        }
        return nil
    }
}

// MARK: - Connection (single-threaded usage)

/// A synchronous VIA Raw HID connection. All calls must happen on one thread/queue.
public final class VIAConnection {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var received: [[UInt8]] = []
    private let runLoop: CFRunLoop
    private var closed = false

    public let discovered: VIADevice

    public convenience init(device: VIADevice? = nil) throws {
        try self.init(device: device, ignored: ())
    }

    private init(device: VIADevice?, ignored: Void) throws {
        runLoop = CFRunLoopGetCurrent()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, nil)
        // The manager open can fail with kIOReturnNotPermitted for the protected keyboard
        // interfaces while the vendor collection remains usable, so it is intentionally
        // not treated as fatal. The device open below is the real permission check.
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !deviceSet.isEmpty else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
            throw VIAError.deviceNotFound
        }

        let described = deviceSet.compactMap { candidate -> (IOHIDDevice, VIADevice)? in
            guard let info = VIADiscovery.describe(candidate) else { return nil }
            return (candidate, info)
        }
        let chosen = device.flatMap { wanted in
            described.first {
                $0.1.vendorID == wanted.vendorID &&
                $0.1.productID == wanted.productID &&
                $0.1.locationID == wanted.locationID
            }
        } ?? described.sorted { $0.1.id < $1.1.id }.first
        let target = chosen?.0
        let foundInfo = chosen?.1
        guard let device = target, let info = foundInfo else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
            throw VIAError.deviceNotFound
        }
        self.discovered = info

        let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if UInt32(bitPattern: status) == 0xE00002E2 {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
            throw VIAError.permissionDenied
        }
        guard status == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
            throw VIAError.openFailed(status)
        }

        self.device = device
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        buffer.initialize(repeating: 0, count: 64)
        self.inputBuffer = buffer
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            64,
            { context, _, _, _, _, report, reportLength in
                guard let context = context, reportLength > 0 else { return }
                let connection = Unmanaged<VIAConnection>.fromOpaque(context).takeUnretainedValue()
                connection.noteReport(Array(UnsafeBufferPointer(start: report, count: Int(reportLength))))
            },
            context
        )
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        close()
    }

    private func noteReport(_ bytes: [UInt8]) {
        received.append(bytes)
        if received.count > 16 {
            received.removeFirst(received.count - 16)
        }
    }

    public func request(_ payload: [UInt8], timeout: TimeInterval = 0.4) throws -> [UInt8] {
        guard !closed, let device = device else { throw VIAError.notConnected }
        guard !payload.isEmpty else { throw VIAError.invalidResponse(command: 0, response: []) }

        var report = [UInt8](repeating: 0, count: AppConstants.reportSize)
        for (index, byte) in payload.enumerated() where index < report.count {
            report[index] = byte
        }

        // Drain anything left over from earlier commands.
        received.removeAll(keepingCapacity: true)
        _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.002, true)
        received.removeAll(keepingCapacity: true)

        let status: IOReturn = report.withUnsafeBufferPointer { pointer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, pointer.baseAddress!, report.count)
        }
        if status != kIOReturnSuccess {
            throw VIAError.openFailed(status)
        }

        let command = payload[0]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.01, true)
            if let match = received.first(where: { $0.count >= 2 && $0[0] == command }) {
                return match
            }
        }
        throw VIAError.timeout(command: command)
    }

    public func close() {
        guard !closed else { return }
        closed = true
        if let device = device {
            IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager = manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        inputBuffer?.deallocate()
        inputBuffer = nil
        device = nil
        manager = nil
    }
}
