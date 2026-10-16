/*
* Copyright (c) 2026, Nordic Semiconductor
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without modification,
* are permitted provided that the following conditions are met:
*
* 1. Redistributions of source code must retain the above copyright notice, this
*    list of conditions and the following disclaimer.
*
* 2. Redistributions in binary form must reproduce the above copyright notice, this
*    list of conditions and the following disclaimer in the documentation and/or
*    other materials provided with the distribution.
*
* 3. Neither the name of the copyright holder nor the names of its contributors may
*    be used to endorse or promote products derived from this software without
*    specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
* ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
* IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
* INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
* NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
* PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
* WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
* ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
* POSSIBILITY OF SUCH DAMAGE.
*/

import XCTest
@testable import CoreBluetoothMock

/// Conformance tests of the peripheral role.
///
/// The test publishes a service, advertises it and records everything the peripheral manager
/// reports to its delegate while a central runs a fixed script (see below).
///
/// - On a **simulator** the mock implementation is used, and the script is executed by
///   a ``CBMCentralSpec``.
/// - On a **physical iPhone** the native implementation is used and the test waits for
///   a real central to run the script. The `Example/Scripts/PeripheralConformanceCentral.swift`
///   macOS tool executes it on a Mac.
///
/// The script: scan, connect, read `read`, read `cached`, write `write`, write `read` (not
/// writable), write `writeNoResponse`, subscribe to `notify`, receive notifications,
/// unsubscribe, write `done`, disconnect.
///
/// Only behavior common to both is asserted. All events are printed with the `PCONF:` prefix.
///
/// - Note: The native run was not completed yet. On the iPhone 13 (iOS 26.6) used to develop
///         this test, neither this test nor a plain `CBPeripheralManager` advertisement was
///         visible to other devices (a Mac, and a separate scanner), so the central could not
///         connect. The script, the expected events and the Mac tool are ready for another try
///         on a different device.
class PeripheralConformanceTest: XCTestCase {
    static let serviceUUID = CBMUUID(string: "A0000001-0000-4000-8000-00805F9B34FB")
    static let readUUID = CBMUUID(string: "A0000002-0000-4000-8000-00805F9B34FB")
    static let cachedUUID = CBMUUID(string: "A0000003-0000-4000-8000-00805F9B34FB")
    static let writeUUID = CBMUUID(string: "A0000004-0000-4000-8000-00805F9B34FB")
    static let writeNoResponseUUID = CBMUUID(string: "A0000005-0000-4000-8000-00805F9B34FB")
    static let notifyUUID = CBMUUID(string: "A0000006-0000-4000-8000-00805F9B34FB")
    static let doneUUID = CBMUUID(string: "A0000007-0000-4000-8000-00805F9B34FB")
    static let localName = "ConfTest"

    #if targetEnvironment(simulator)
    private let isMock = true
    #else
    private let isMock = false
    #endif

    private var manager: CBMPeripheralManager!
    private var delegate: Delegate!
    private var central: CBMCentralSpec!
    private var script: MockCentralScript?

    override func setUpWithError() throws {
        if isMock {
            CBMCentralManagerMock.simulateInitialState(.poweredOn)
        }
    }

    override func tearDownWithError() throws {
        UIApplication.shared.isIdleTimerDisabled = false
        manager?.stopAdvertising()
        manager?.removeAllServices()
        manager = nil
        delegate = nil
        central = nil
        script = nil
        if isMock {
            CBMCentralManagerMock.simulatePowerOff()
            CBMPeripheralManagerMock.tearDown()
        }
    }

    // MARK: - Delegate recording events

    private final class Delegate: NSObject, CBMPeripheralManagerDelegate {
        var events: [String] = []
        var onEvent: ((String) -> Void)?
        var onDone: (() -> Void)?
        var onSubscribe: (() -> Void)?
        var service: CBMMutableService?
        var notify: CBMMutableCharacteristic?
        var advertisement: [String : Any] = [:]

        private func characteristicName(_ uuid: CBMUUID) -> String {
            switch uuid {
            case PeripheralConformanceTest.readUUID: return "read"
            case PeripheralConformanceTest.cachedUUID: return "cached"
            case PeripheralConformanceTest.writeUUID: return "write"
            case PeripheralConformanceTest.writeNoResponseUUID: return "writeNoResponse"
            case PeripheralConformanceTest.notifyUUID: return "notify"
            case PeripheralConformanceTest.doneUUID: return "done"
            default: return uuid.uuidString
            }
        }

        func record(_ event: String) {
            events.append(event)
            NSLog("PCONF: \(event)")
            onEvent?(event)
        }

        func peripheralManagerDidUpdateState(_ peripheral: CBMPeripheralManager) {
            record("state \(peripheral.state.rawValue)")
            if peripheral.state == .poweredOn, let service = service {
                peripheral.add(service)
            }
        }

        func peripheralManager(_ peripheral: CBMPeripheralManager, didAdd service: CBMService, error: Error?) {
            record("didAdd \(service.uuid) error=\(error == nil ? "nil" : "\(error!)")")
            peripheral.startAdvertising(advertisement)
        }

        func peripheralManagerDidStartAdvertising(_ peripheral: CBMPeripheralManager, error: Error?) {
            record("didStartAdvertising error=\(error == nil ? "nil" : "\(error!)") isAdvertising=\(peripheral.isAdvertising)")
        }

        func peripheralManager(_ peripheral: CBMPeripheralManager, central: CBMCentral,
                               didSubscribeTo characteristic: CBMCharacteristic) {
            record("didSubscribeTo \(characteristic.uuid) maximumUpdateValueLength>=20=\(central.maximumUpdateValueLength >= 20) subscribed=\((characteristic as? CBMMutableCharacteristic)?.subscribedCentrals?.count ?? -1)")
            onSubscribe?()
            guard let notify = notify else { return }
            // Longer than any update can be, so the value is truncated.
            for i in 0..<3 {
                let accepted = peripheral.updateValue(Data(repeating: UInt8(i + 1), count: 600),
                                                      for: notify, onSubscribedCentrals: nil)
                record("updateValue #\(i + 1) -> \(accepted)")
            }
        }

        func peripheralManager(_ peripheral: CBMPeripheralManager, central: CBMCentral,
                               didUnsubscribeFrom characteristic: CBMCharacteristic) {
            record("didUnsubscribeFrom \(characteristic.uuid) subscribed=\((characteristic as? CBMMutableCharacteristic)?.subscribedCentrals?.count ?? -1)")
        }

        func peripheralManager(_ peripheral: CBMPeripheralManager, didReceiveRead request: CBMATTRequest) {
            record("didReceiveRead \(characteristicName(request.characteristic.uuid)) offset=\(request.offset) value=\(String(describing: request.value))")
            request.value = Data([0x10, 0x20, 0x30, 0x40, 0x50])
            peripheral.respond(to: request, withResult: .success)
        }

        func peripheralManager(_ peripheral: CBMPeripheralManager, didReceiveWrite requests: [CBMATTRequest]) {
            let description = requests
                .map { "\(characteristicName($0.characteristic.uuid)) offset=\($0.offset) value=\($0.value?.map { String(format: "%02x", $0) }.joined() ?? "nil")" }
                .joined(separator: ", ")
            record("didReceiveWrite count=\(requests.count) [\(description)]")
            guard let first = requests.first else { return }
            if first.characteristic.uuid == PeripheralConformanceTest.writeNoResponseUUID {
                // Write commands are not responded to.
            } else {
                peripheral.respond(to: first, withResult: .success)
            }
            if first.characteristic.uuid == PeripheralConformanceTest.doneUUID {
                onDone?()
            }
        }

        func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBMPeripheralManager) {
            record("isReadyToUpdateSubscribers")
        }
    }

    // MARK: - Test

    func testPeripheralRole() throws {
        let read = CBMMutableCharacteristic(type: Self.readUUID, properties: [.read], value: nil,
                                            permissions: [.readable])
        let cached = CBMMutableCharacteristic(type: Self.cachedUUID, properties: [.read],
                                              value: Data([0xCA, 0xCE]), permissions: [.readable])
        let write = CBMMutableCharacteristic(type: Self.writeUUID, properties: [.write], value: nil,
                                             permissions: [.writeable])
        let writeNoResponse = CBMMutableCharacteristic(type: Self.writeNoResponseUUID,
                                                       properties: [.writeWithoutResponse], value: nil,
                                                       permissions: [.writeable])
        let notify = CBMMutableCharacteristic(type: Self.notifyUUID, properties: [.notify], value: nil,
                                              permissions: [])
        let done = CBMMutableCharacteristic(type: Self.doneUUID, properties: [.write], value: nil,
                                            permissions: [.writeable])
        let service = CBMMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [read, cached, write, writeNoResponse, notify, done]

        delegate = Delegate()
        delegate.service = service
        delegate.notify = notify
        delegate.advertisement = [
            CBMAdvertisementDataLocalNameKey: Self.localName,
            CBMAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]
        ]
        let finished = expectation(description: "Central finished the script")
        delegate.onDone = { finished.fulfill() }

        if isMock {
            central = CBMCentralSpec(maximumUpdateValueLength: 20, connectionInterval: 0.02)
            script = MockCentralScript(central: central, service: service)
            delegate.onEvent = { [unowned self] event in
                if event.hasPrefix("didStartAdvertising") {
                    self.script?.start()
                }
            }
        } else {
            NSLog("PCONF: waiting for a central. Run the PeripheralConformanceCentral tool on a Mac. Keep the device unlocked, with the app in the foreground.")
            // Advertising data (local name, service UUIDs) is only complete when the app
            // is active. Advertising started earlier stays limited.
            if UIApplication.shared.applicationState != .active {
                let active = expectation(forNotification: UIApplication.didBecomeActiveNotification, object: nil)
                wait(for: [active], timeout: 30)
            }
            NSLog("PCONF: applicationState \(UIApplication.shared.applicationState.rawValue) (0 = active), protected data available: \(UIApplication.shared.isProtectedDataAvailable)")
            // Do not let the device lock during the test.
            UIApplication.shared.isIdleTimerDisabled = true
            for delay in [10.0, 20.0, 30.0, 45.0, 60.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    NSLog("PCONF: +\(delay)s applicationState \(UIApplication.shared.applicationState.rawValue) isAdvertising=\(String(describing: self?.manager?.isAdvertising))")
                }
            }
        }

        manager = CBMPeripheralManagerFactory.instance(delegate: delegate, queue: nil, forceMock: isMock)
        wait(for: [finished], timeout: isMock ? 20 : 180)
        // Let the remaining events (e.g. disconnection) arrive.
        let settle = expectation(description: "Settle")
        settle.isInverted = true
        wait(for: [settle], timeout: 2)

        // MARK: Assertions on the common behavior.
        let events = delegate.events
        func index(of prefix: String) -> Int? { events.firstIndex { $0.hasPrefix(prefix) } }

        XCTAssertEqual(events.first, "state 5")
        let added = try XCTUnwrap(index(of: "didAdd \(Self.serviceUUID)"))
        XCTAssertTrue(events[added].hasSuffix("error=nil"))
        let started = try XCTUnwrap(index(of: "didStartAdvertising"))
        XCTAssertTrue(events[started].contains("error=nil"))
        XCTAssertGreaterThan(started, added)

        // Reads and writes reach the delegate with offsets and values.
        XCTAssertNotNil(events.firstIndex { $0 == "didReceiveRead read offset=0 value=nil" })
        XCTAssertNotNil(events.firstIndex { $0 == "didReceiveWrite count=1 [write offset=0 value=010203]" })
        XCTAssertNotNil(events.firstIndex { $0 == "didReceiveWrite count=1 [writeNoResponse offset=0 value=0909]" })
        XCTAssertNotNil(events.firstIndex { $0 == "didReceiveWrite count=1 [done offset=0 value=01]" })
        // A cached value is answered by the system, and a write to a read-only
        // characteristic is rejected by the system.
        XCTAssertNil(events.first { $0.hasPrefix("didReceiveRead cached") })
        XCTAssertNil(events.first { $0.contains("[read offset") && $0.hasPrefix("didReceiveWrite") })

        // Subscription.
        let subscribed = try XCTUnwrap(index(of: "didSubscribeTo \(Self.notifyUUID)"))
        XCTAssertTrue(events[subscribed].contains("maximumUpdateValueLength>=20=true"))
        let unsubscribed = try XCTUnwrap(index(of: "didUnsubscribeFrom \(Self.notifyUUID)"))
        XCTAssertGreaterThan(unsubscribed, subscribed)
        XCTAssertEqual(events.filter { $0.hasPrefix("updateValue") && $0.hasSuffix("true") }.count, 3)

        if isMock {
            // Observations of the simulated central.
            XCTAssertEqual(script?.notificationLengths, [20, 20, 20])
            XCTAssertEqual(script?.log.contains("write read -> error 3"), true, "\(script?.log ?? [])")
        }
    }
}

// MARK: - Mock central

/// Runs the script of the conformance test using a mock central.
private final class MockCentralScript: CBMCentralSpecDelegate {
    private let central: CBMCentralSpec
    private let service: CBMMutableService
    private(set) var log: [String] = []
    private(set) var notificationLengths: [Int] = []
    private var characteristics: [CBMUUID : CBMMutableCharacteristic] = [:]

    init(central: CBMCentralSpec, service: CBMMutableService) {
        self.central = central
        self.service = service
        central.delegate = self
    }

    private func note(_ text: String) {
        log.append(text)
        NSLog("CCONF: \(text)")
    }

    func central(_ central: CBMCentralSpec, didReceiveUpdate value: Data,
                 for characteristic: CBMMutableCharacteristic) {
        notificationLengths.append(value.count)
        note("notification \(value.count) bytes")
    }

    func start() {
        guard let advertisement = central.simulateScan(withServices: [PeripheralConformanceTest.serviceUUID]) else {
            note("scan: nothing found")
            return
        }
        note("scan: \(advertisement[CBMAdvertisementDataLocalNameKey] ?? "?")")
        central.simulateConnection()
        for c in central.simulateCharacteristicDiscovery(forService: PeripheralConformanceTest.serviceUUID) {
            characteristics[c.uuid] = c
        }
        note("discovered \(characteristics.count) characteristics")
        step1()
    }

    private func step1() {
        central.simulateReadRequest(for: characteristics[PeripheralConformanceTest.readUUID]!) { [self] result in
            note("read read -> \(describe(result))")
            central.simulateReadRequest(for: characteristics[PeripheralConformanceTest.cachedUUID]!) { [self] result in
                note("read cached -> \(describe(result))")
                step2()
            }
        }
    }

    private func step2() {
        central.simulateWriteRequest(Data([1, 2, 3]), for: characteristics[PeripheralConformanceTest.writeUUID]!) { [self] result in
            note("write write -> \(describe(result))")
            central.simulateWriteRequest(Data([1]), for: characteristics[PeripheralConformanceTest.readUUID]!) { [self] result in
                note("write read -> \(describe(result))")
                central.simulateWriteRequestWithoutResponse(Data([9, 9]),
                                                            for: characteristics[PeripheralConformanceTest.writeNoResponseUUID]!)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                    step3()
                }
            }
        }
    }

    private func step3() {
        let notify = characteristics[PeripheralConformanceTest.notifyUUID]!
        central.simulateSubscription(to: notify)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            central.simulateUnsubscription(from: notify)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                central.simulateWriteRequest(Data([1]), for: characteristics[PeripheralConformanceTest.doneUUID]!) { [self] result in
                    note("write done -> \(describe(result))")
                    central.simulateDisconnection()
                }
            }
        }
    }

    private func describe<T>(_ result: Result<T, Error>) -> String {
        switch result {
        case .success(let value):
            if let data = value as? Data {
                return data.map { String(format: "%02x", $0) }.joined()
            }
            return "ok"
        case .failure(let error):
            return "error \((error as NSError).code)"
        }
    }
}
