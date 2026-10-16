// A macOS tool that plays the central role for `PeripheralConformanceTest`.
//
// It runs the same script as the mock central of the test: scan, connect, read, write,
// subscribe, unsubscribe, write "done" and disconnect. Build and run it using
// `build-peripheral-conformance-central.sh`. Output lines are prefixed with `CCONF:`.

import CoreBluetooth
import Foundation

let service = CBUUID(string: "A0000001-0000-4000-8000-00805F9B34FB")
let readUUID = CBUUID(string: "A0000002-0000-4000-8000-00805F9B34FB")
let cachedUUID = CBUUID(string: "A0000003-0000-4000-8000-00805F9B34FB")
let writeUUID = CBUUID(string: "A0000004-0000-4000-8000-00805F9B34FB")
let writeNoResponseUUID = CBUUID(string: "A0000005-0000-4000-8000-00805F9B34FB")
let notifyUUID = CBUUID(string: "A0000006-0000-4000-8000-00805F9B34FB")
let doneUUID = CBUUID(string: "A0000007-0000-4000-8000-00805F9B34FB")

let verbose = CommandLine.arguments.contains("all")

func note(_ text: String) {
    print("CCONF: [\(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))] \(text)")
    fflush(stdout)
}

func hex(_ data: Data?) -> String {
    return data?.map { String(format: "%02x", $0) }.joined() ?? "nil"
}

func describe(_ error: Error?) -> String {
    guard let error = error as NSError? else { return "ok" }
    return "error \(error.code)"
}

final class Runner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var manager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristics: [CBUUID : CBCharacteristic] = [:]
    private var steps: [() -> Void] = []
    private var notifications = 0

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: nil)
    }

    private func next() {
        guard !steps.isEmpty else { return }
        steps.removeFirst()()
    }

    private func after(_ delay: TimeInterval, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }

    // MARK: Central

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        note("state \(central.state.rawValue)")
        if central.state == .poweredOn {
            // With the "all" argument no service filter is used, and all advertisements are
            // logged. This helps when the device is not found, e.g. when the iPhone app is in
            // the background and does not advertise its service UUIDs.
            central.scanForPeripherals(withServices: verbose ? nil : [service],
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "?"
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
        if verbose {
            note("seen \(peripheral.identifier.uuidString.prefix(8)) name=\(name) services=\(services) overflow=\(overflow) rssi=\(RSSI) keys=\(advertisementData.keys.sorted())")
            guard services.contains(service) || overflow.contains(service) || name == "ConfTest" else { return }
        }
        note("scan: \(name)")
        self.peripheral = peripheral
        central.stopScan()
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        note("connected")
        steps = [
            { peripheral.discoverServices([service]) },
            { [self] in readChar(readUUID, "read") },
            { [self] in readChar(cachedUUID, "cached") },
            { [self] in writeChar(writeUUID, Data([1, 2, 3]), "write") },
            { [self] in writeChar(readUUID, Data([1]), "read") },
            { [self] in
                peripheral.writeValue(Data([9, 9]), for: characteristics[writeNoResponseUUID]!, type: .withoutResponse)
                note("write writeNoResponse -> sent")
                after(0.5) { self.next() }
            },
            { [self] in peripheral.setNotifyValue(true, for: characteristics[notifyUUID]!) },
            { [self] in after(2.0) { self.next() } },
            { [self] in peripheral.setNotifyValue(false, for: characteristics[notifyUUID]!) },
            { [self] in after(0.5) { self.next() } },
            { [self] in writeChar(doneUUID, Data([1]), "done") },
            { [self] in
                after(0.5) {
                    note("cancelling connection")
                    central.cancelPeripheralConnection(peripheral)
                }
            }
        ]
        next()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        note("disconnected \(describe(error))")
        exit(0)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        note("failed to connect \(describe(error))")
        exit(1)
    }

    // MARK: Peripheral

    private func readChar(_ uuid: CBUUID, _ name: String) {
        pendingReadName = name
        peripheral?.readValue(for: characteristics[uuid]!)
    }

    private func writeChar(_ uuid: CBUUID, _ data: Data, _ name: String) {
        pendingWriteName = name
        peripheral?.writeValue(data, for: characteristics[uuid]!, type: .withResponse)
    }

    private var pendingReadName = ""
    private var pendingWriteName = ""

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = peripheral.services?.first else { note("no service \(describe(error))"); exit(1) }
        peripheral.discoverCharacteristics(nil, for: s)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] { characteristics[c.uuid] = c }
        note("discovered \(characteristics.count) characteristics")
        note("maximumWriteValueLength withoutResponse=\(peripheral.maximumWriteValueLength(for: .withoutResponse))")
        next()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == notifyUUID {
            notifications += 1
            note("notification \(characteristic.value?.count ?? -1) bytes")
        } else {
            note("read \(pendingReadName) -> \(error == nil ? hex(characteristic.value) : describe(error))")
            next()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        note("write \(pendingWriteName) -> \(describe(error))")
        next()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        note("notify state \(characteristic.isNotifying) \(describe(error))")
        next()
    }
}

let runner = Runner()
DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
    note("timeout")
    exit(2)
}
withExtendedLifetime(runner) { RunLoop.main.run() }
