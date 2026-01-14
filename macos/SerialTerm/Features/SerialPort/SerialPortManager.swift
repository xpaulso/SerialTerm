import Foundation
import IOKit
import IOKit.serial

/// Serial port information
struct SerialPortInfo: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let name: String
    let vendorID: Int?
    let productID: Int?

    var displayName: String {
        if name.isEmpty {
            return path.replacingOccurrences(of: "/dev/cu.", with: "")
        }
        return name
    }
}

/// Manages serial port enumeration and monitoring
@MainActor
final class SerialPortManager: ObservableObject {
    static let shared = SerialPortManager()

    @Published private(set) var availablePorts: [SerialPortInfo] = []

    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    init() {
        setupNotifications()
        enumeratePorts()
    }

    deinit {
        // Clean up IOKit resources
        // Note: These are simple integer/pointer types that are safe to access
        let port = notificationPort
        let added = addedIterator
        let removed = removedIterator

        if let port = port {
            IONotificationPortDestroy(port)
        }
        if added != 0 {
            IOObjectRelease(added)
        }
        if removed != 0 {
            IOObjectRelease(removed)
        }
    }

    private func setupNotifications() {
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notificationPort else { return }

        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        matchingDict[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Watch for device additions
        let addedResult = IOServiceAddMatchingNotification(
            port,
            kIOPublishNotification,
            (matchingDict.copy() as! CFDictionary),
            { refCon, iterator in
                guard let refCon = refCon else { return }
                let manager = Unmanaged<SerialPortManager>.fromOpaque(refCon).takeUnretainedValue()
                // Drain iterator
                var service = IOIteratorNext(iterator)
                while service != 0 {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                Task { @MainActor in
                    manager.enumeratePorts()
                }
            },
            selfPtr,
            &addedIterator
        )

        // Watch for device removals
        let removedResult = IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            matchingDict as CFDictionary,
            { refCon, iterator in
                guard let refCon = refCon else { return }
                let manager = Unmanaged<SerialPortManager>.fromOpaque(refCon).takeUnretainedValue()
                // Drain iterator
                var service = IOIteratorNext(iterator)
                while service != 0 {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                Task { @MainActor in
                    manager.enumeratePorts()
                }
            },
            selfPtr,
            &removedIterator
        )

        // Drain initial iterators
        if addedResult == KERN_SUCCESS {
            drainIterator(addedIterator)
        }
        if removedResult == KERN_SUCCESS {
            drainIterator(removedIterator)
        }
    }

    func enumeratePorts() {
        var iterator: io_iterator_t = 0
        let matchingDict = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        matchingDict[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes

        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matchingDict as CFDictionary,
            &iterator
        )

        guard result == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var ports: [SerialPortInfo] = []
        var service = IOIteratorNext(iterator)

        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let path = getStringProperty(service, kIOCalloutDeviceKey as CFString),
                  path.hasPrefix("/dev/cu.") else { continue }

            let name = getStringProperty(service, kIOTTYDeviceKey as CFString) ?? ""
            let vendorID = getIntProperty(service, "idVendor" as CFString)
            let productID = getIntProperty(service, "idProduct" as CFString)

            ports.append(SerialPortInfo(
                id: path,
                path: path,
                name: name,
                vendorID: vendorID,
                productID: productID
            ))
        }

        self.availablePorts = ports.sorted { $0.path < $1.path }
    }

    private func getStringProperty(_ service: io_object_t, _ key: CFString) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(
            service, key, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return value as? String
    }

    private func getIntProperty(_ service: io_object_t, _ key: CFString) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(
            service, key, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return value as? Int
    }

    private func drainIterator(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}
