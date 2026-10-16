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
@testable import nRF_Blinky
@testable import CoreBluetoothMock

/// Conformance tests of the central role.
///
/// The same tests run on a simulator, where they use the mock implementation with the
/// simulated nRF Blinky, and on a physical iPhone, where they use the native implementation
/// with a real device advertising the LED Button Service (LBS), e.g. a DK running the
/// Zephyr *Peripheral LBS* sample, named "nRF54L15", "Nordic_Blinky" or "nRF Blinky".
///
/// Their purpose is to make sure that the mock behaves like the native Core Bluetooth.
/// Only behavior that is common for both is asserted. Each test prints observations
/// prefixed with `CONFORMANCE:`.
class CentralConformanceTest: XCTestCase {
    private let lbs = CBMUUID(string: "00001523-1212-EFDE-1523-785FEABCD123")
    private let buttonUUID = CBMUUID(string: "00001524-1212-EFDE-1523-785FEABCD123")
    private let ledUUID = CBMUUID(string: "00001525-1212-EFDE-1523-785FEABCD123")
    private let deviceNames = ["nRF54L15", "Nordic_Blinky", "nRF Blinky"]

    private let managerDelegate = CBMCentralManagerDelegateProxy()
    private let peripheralDelegate = CBMPeripheralDelegateProxy()
    private var manager: CBMCentralManager!
    private var log: [String] = []

    #if targetEnvironment(simulator)
    private let isMock = true
    #else
    private let isMock = false
    #endif

    override func setUpWithError() throws {
        log = []
        if isMock {
            CBMCentralManagerMock.simulateRSSIDeviation(.none)
            CBMCentralManagerMock.simulatePeripherals([blinky])
            CBMCentralManagerMock.simulateInitialState(.poweredOn)
            blinky.simulateProximityChange(.immediate)
        }
    }

    override func tearDownWithError() throws {
        if let manager = manager, manager.state == .poweredOn {
            manager.stopScan()
        }
        managerDelegate.didUpdateState = nil
        managerDelegate.didDiscoverPeripheral = nil
        managerDelegate.didConnect = nil
        managerDelegate.didFailToConnect = nil
        managerDelegate.didDisconnect = nil
        manager = nil
        if isMock {
            powerOffAndSettle()
            CBMCentralManagerMock.simulateRSSIDeviation(.default)
        }
    }

    // MARK: - Helpers

    private func note(_ text: String) {
        log.append(text)
        NSLog("CONFORMANCE: \(name): \(text)")
    }

    private func waitFor(_ description: String,
                         timeout: TimeInterval = 10.0,
                         inverted: Bool = false,
                         _ body: (XCTestExpectation) -> Void) {
        let expectation = XCTestExpectation(description: description)
        expectation.isInverted = inverted
        body(expectation)
        wait(for: [expectation], timeout: timeout)
    }

    private func pause(_ interval: TimeInterval) {
        waitFor("Pause", timeout: interval, inverted: true) { _ in }
    }

    private func createManager() {
        waitFor("Manager ready") { ready in
            managerDelegate.didUpdateState = { _ in ready.fulfill() }
            manager = CBMCentralManagerFactory.instance(delegate: managerDelegate, queue: nil,
                                                        forceMock: isMock)
        }
        managerDelegate.didUpdateState = nil
    }

    /// Scans for the test device and returns its peripheral.
    private func findDevice() throws -> CBMPeripheral {
        var found: CBMPeripheral?
        waitFor("Device found", timeout: 20.0) { discovered in
            managerDelegate.didDiscoverPeripheral = { [unowned self] _, peripheral, advertisementData, rssi in
                let name = advertisementData[CBMAdvertisementDataLocalNameKey] as? String ?? peripheral.name
                guard found == nil, let name = name, self.deviceNames.contains(name) else { return }
                found = peripheral
                self.note("discovered \"\(name)\" rssi=\(rssi) adv=\(advertisementData.keys.sorted())")
                discovered.fulfill()
            }
            manager.scanForPeripherals(withServices: [lbs])
        }
        manager.stopScan()
        managerDelegate.didDiscoverPeripheral = nil
        return try XCTUnwrap(found, "Test device not found. Is it advertising?")
    }

    private func connect(_ peripheral: CBMPeripheral) {
        peripheral.delegate = peripheralDelegate
        waitFor("Connected") { connected in
            managerDelegate.didConnect = { _, _ in connected.fulfill() }
            manager.connect(peripheral)
        }
        managerDelegate.didConnect = nil
    }

    private func disconnect(_ peripheral: CBMPeripheral) {
        guard peripheral.state != .disconnected else { return }
        waitFor("Disconnected") { disconnected in
            managerDelegate.didDisconnect = { _, _, _, _, _ in disconnected.fulfill() }
            manager.cancelPeripheralConnection(peripheral)
        }
        managerDelegate.didDisconnect = nil
    }

    private func discoverLBS(_ peripheral: CBMPeripheral) throws -> (button: CBMCharacteristic, led: CBMCharacteristic) {
        waitFor("Services discovered") { discovered in
            peripheralDelegate.didDiscoverServices = { _, _ in discovered.fulfill() }
            peripheral.discoverServices([lbs])
        }
        let service = try XCTUnwrap(peripheral.services?.first { $0.uuid == lbs })
        waitFor("Characteristics discovered") { discovered in
            peripheralDelegate.didDiscoverCharacteristics = { _, _, _ in discovered.fulfill() }
            peripheral.discoverCharacteristics(nil, for: service)
        }
        let button = try XCTUnwrap(service.characteristics?.first { $0.uuid == buttonUUID })
        let led = try XCTUnwrap(service.characteristics?.first { $0.uuid == ledUUID })
        return (button, led)
    }

    // MARK: - Tests

    func testStateIsUnknownUntilTheDelegateIsCalled() {
        var states: [CBMManagerState] = []
        waitFor("State reported") { ready in
            managerDelegate.didUpdateState = { [unowned self] manager in
                states.append(manager.state)
                self.note("didUpdateState \(manager.state.rawValue)")
                ready.fulfill()
            }
            manager = CBMCentralManagerFactory.instance(delegate: managerDelegate, queue: nil,
                                                        forceMock: isMock)
            XCTAssertEqual(manager.state, .unknown)
        }
        XCTAssertEqual(states, [.poweredOn])
    }

    func testDiscovery() throws {
        createManager()
        var advertisementData: [String : Any] = [:]
        var rssi = 0
        var peripheral: CBMPeripheral?
        waitFor("Device found", timeout: 20.0) { discovered in
            managerDelegate.didDiscoverPeripheral = { [unowned self] _, p, data, RSSI in
                let name = data[CBMAdvertisementDataLocalNameKey] as? String ?? p.name
                guard peripheral == nil, let name = name, self.deviceNames.contains(name) else { return }
                peripheral = p
                advertisementData = data
                rssi = RSSI.intValue
                discovered.fulfill()
            }
            manager.scanForPeripherals(withServices: [lbs])
            XCTAssertTrue(manager.isScanning)
        }
        manager.stopScan()
        XCTAssertFalse(manager.isScanning)

        let found = try XCTUnwrap(peripheral)
        note("name=\(String(describing: found.name)) adv=\(advertisementData)")
        XCTAssertEqual(found.state, .disconnected)
        XCTAssertLessThan(rssi, 0)
        XCTAssertNotNil(found.name)
        XCTAssertNil(found.services)
        let services = advertisementData[CBMAdvertisementDataServiceUUIDsKey] as? [CBMUUID]
        XCTAssertEqual(services?.contains(lbs), true)
    }

    func testConnectionLifecycle() throws {
        createManager()
        let peripheral = try findDevice()
        peripheral.delegate = peripheralDelegate

        waitFor("Connected") { connected in
            managerDelegate.didConnect = { _, p in
                XCTAssertTrue(p === peripheral)
                XCTAssertEqual(p.state, .connected)
                connected.fulfill()
            }
            manager.connect(peripheral)
            XCTAssertEqual(peripheral.state, .connecting)
        }

        waitFor("Disconnected") { disconnected in
            managerDelegate.didDisconnect = { [unowned self] _, p, _, isReconnecting, error in
                self.note("didDisconnect isReconnecting=\(isReconnecting) error=\(String(describing: error))")
                XCTAssertTrue(p === peripheral)
                XCTAssertFalse(isReconnecting)
                XCTAssertNil(error)
                XCTAssertEqual(p.state, .disconnected)
                disconnected.fulfill()
            }
            manager.cancelPeripheralConnection(peripheral)
            XCTAssertEqual(peripheral.state, .disconnecting)
        }
        XCTAssertNil(peripheral.services)
    }

    func testAttributesAreNilUntilDiscoveryCompletes() throws {
        createManager()
        let peripheral = try findDevice()
        connect(peripheral)
        defer { disconnect(peripheral) }

        XCTAssertNil(peripheral.services)
        waitFor("Services discovered") { discovered in
            peripheralDelegate.didDiscoverServices = { _, error in
                XCTAssertNil(error)
                discovered.fulfill()
            }
            peripheral.discoverServices([lbs])
            XCTAssertNil(peripheral.services)
        }
        let service = try XCTUnwrap(peripheral.services?.first)
        XCTAssertEqual(service.uuid, lbs)
        XCTAssertTrue(service.isPrimary)
        XCTAssertNil(service.characteristics)

        waitFor("Characteristics discovered") { discovered in
            peripheralDelegate.didDiscoverCharacteristics = { _, _, error in
                XCTAssertNil(error)
                discovered.fulfill()
            }
            peripheral.discoverCharacteristics(nil, for: service)
            XCTAssertNil(service.characteristics)
        }
        let characteristics = try XCTUnwrap(service.characteristics)
        XCTAssertEqual(Set(characteristics.map { $0.uuid }), [buttonUUID, ledUUID])
        let button = try XCTUnwrap(characteristics.first { $0.uuid == buttonUUID })
        XCTAssertTrue(button.properties.contains(.notify))
        XCTAssertTrue(button.properties.contains(.read))
        let led = try XCTUnwrap(characteristics.first { $0.uuid == ledUUID })
        XCTAssertTrue(led.properties.contains(.write))
        XCTAssertNil(button.descriptors)

        waitFor("Descriptors discovered") { discovered in
            peripheralDelegate.didDiscoverDescriptors = { _, _, error in
                XCTAssertNil(error)
                discovered.fulfill()
            }
            peripheral.discoverDescriptors(for: button)
            XCTAssertNil(button.descriptors)
        }
        XCTAssertTrue(button.descriptors?.contains { $0.uuid == CBMUUID(string: "2902") } ?? false)
    }

    func testDiscoveringServiceNotOnTheDevice() throws {
        createManager()
        let peripheral = try findDevice()
        connect(peripheral)
        defer { disconnect(peripheral) }

        waitFor("Services discovered") { discovered in
            peripheralDelegate.didDiscoverServices = { [unowned self] p, error in
                self.note("didDiscoverServices services=\(String(describing: p.services)) error=\(String(describing: error))")
                XCTAssertNil(error)
                discovered.fulfill()
            }
            peripheral.discoverServices([CBMUUID(string: "1234")])
        }
        // Nothing was found, so the services stay nil.
        XCTAssertNil(peripheral.services)
        XCTAssertTrue(peripheral.services?.isEmpty ?? true)
    }

    func testDiscoveringCharacteristicNotOnTheService() throws {
        createManager()
        let peripheral = try findDevice()
        connect(peripheral)
        defer { disconnect(peripheral) }
        waitFor("Services discovered") { discovered in
            peripheralDelegate.didDiscoverServices = { _, _ in discovered.fulfill() }
            peripheral.discoverServices([lbs])
        }
        let service = try XCTUnwrap(peripheral.services?.first)

        waitFor("Characteristics discovered") { discovered in
            peripheralDelegate.didDiscoverCharacteristics = { [unowned self] _, s, error in
                self.note("didDiscoverCharacteristics characteristics=\(String(describing: s.characteristics)) error=\(String(describing: error))")
                XCTAssertNil(error)
                discovered.fulfill()
            }
            peripheral.discoverCharacteristics([CBMUUID(string: "1234")], for: service)
        }
        XCTAssertNil(service.characteristics)
    }

    func testReadButton() throws {
        createManager()
        let peripheral = try findDevice()
        connect(peripheral)
        defer { disconnect(peripheral) }
        let (button, _) = try discoverLBS(peripheral)

        waitFor("Value read") { read in
            peripheralDelegate.didUpdateCharacteristicValue = { _, c, error in
                XCTAssertTrue(c === button)
                XCTAssertNil(error)
                read.fulfill()
            }
            peripheral.readValue(for: button)
        }
        XCTAssertEqual(button.value?.count, 1)
    }

    func testWriteLed() throws {
        createManager()
        let peripheral = try findDevice()
        connect(peripheral)
        defer { disconnect(peripheral) }
        let (_, led) = try discoverLBS(peripheral)

        for value in [UInt8(1), UInt8(0)] {
            waitFor("Value written") { written in
                peripheralDelegate.didWriteCharacteristicValue = { _, c, error in
                    XCTAssertTrue(c === led)
                    XCTAssertNil(error)
                    written.fulfill()
                }
                peripheral.writeValue(Data([value]), for: led, type: .withResponse)
            }
        }
    }

    func testMaximumWriteValueLength() throws {
        createManager()
        let peripheral = try findDevice()
        connect(peripheral)
        defer { disconnect(peripheral) }

        let withResponse = peripheral.maximumWriteValueLength(for: .withResponse)
        let withoutResponse = peripheral.maximumWriteValueLength(for: .withoutResponse)
        note("maximumWriteValueLength withResponse=\(withResponse) withoutResponse=\(withoutResponse) canSend=\(peripheral.canSendWriteWithoutResponse)")
        XCTAssertEqual(withResponse, 512)
        XCTAssertGreaterThanOrEqual(withoutResponse, 20)
        XCTAssertTrue(peripheral.canSendWriteWithoutResponse)
    }

    func testNotificationState() throws {
        createManager()
        let peripheral = try findDevice()
        connect(peripheral)
        let (button, _) = try discoverLBS(peripheral)

        waitFor("Notifications enabled") { enabled in
            peripheralDelegate.didUpdateNotificationState = { _, c, error in
                XCTAssertNil(error)
                XCTAssertTrue(c.isNotifying)
                enabled.fulfill()
            }
            peripheral.setNotifyValue(true, for: button)
            XCTAssertFalse(button.isNotifying)
        }

        // Enabling again: the delegate is still called.
        var reported = false
        waitFor("Notification state reported again", timeout: 3.0) { again in
            peripheralDelegate.didUpdateNotificationState = { [unowned self] _, c, error in
                self.note("second didUpdateNotificationState isNotifying=\(c.isNotifying) error=\(String(describing: error))")
                reported = true
                again.fulfill()
            }
            peripheral.setNotifyValue(true, for: button)
        }
        XCTAssertTrue(reported)

        disconnect(peripheral)
        // Notification state is not retained by the central after reconnection.
        connect(peripheral)
        defer { disconnect(peripheral) }
        let (reconnectedButton, _) = try discoverLBS(peripheral)
        XCTAssertFalse(reconnectedButton.isNotifying)
    }

    func testReadRSSI() throws {
        createManager()
        let peripheral = try findDevice()
        connect(peripheral)
        defer { disconnect(peripheral) }

        waitFor("RSSI read") { read in
            peripheralDelegate.didReadRSSI = { _, rssi, error in
                XCTAssertNil(error)
                XCTAssertLessThan(rssi.intValue, 0)
                read.fulfill()
            }
            peripheral.readRSSI()
        }
    }

    func testRetrieval() throws {
        createManager()
        let peripheral = try findDevice()

        let retrieved = manager.retrievePeripherals(withIdentifiers: [peripheral.identifier, UUID()])
        XCTAssertEqual(retrieved.count, 1)
        XCTAssertTrue(retrieved.first === peripheral)
        XCTAssertTrue(manager.retrieveConnectedPeripherals(withServices: [lbs]).filter { $0 === peripheral }.isEmpty)

        connect(peripheral)
        defer { disconnect(peripheral) }
        _ = try discoverLBS(peripheral)
        let connected = manager.retrieveConnectedPeripherals(withServices: [lbs])
        note("retrieveConnectedPeripherals count=\(connected.count) same=\(connected.contains { $0 === peripheral })")
        XCTAssertTrue(connected.contains { $0.identifier == peripheral.identifier })
    }

    func testPeripheralDelegateIsWeak() throws {
        createManager()
        let peripheral = try findDevice()
        autoreleasepool {
            peripheral.delegate = CBMPeripheralDelegateProxy()
        }
        XCTAssertNil(peripheral.delegate)
    }

    /// Cancelling a connection that is still pending. The expected behavior is not
    /// documented; this test records what the implementation does.
    func testCancellingPendingConnection() throws {
        createManager()
        let peripheral = try findDevice()
        peripheral.delegate = peripheralDelegate

        var events: [String] = []
        managerDelegate.didConnect = { _, _ in events.append("didConnect") }
        managerDelegate.didFailToConnect = { _, _, error in events.append("didFailToConnect(\(String(describing: error)))") }
        managerDelegate.didDisconnect = { _, _, _, isReconnecting, error in
            events.append("didDisconnect(isReconnecting: \(isReconnecting), error: \(String(describing: error)))")
        }
        manager.connect(peripheral)
        note("after connect: state=\(peripheral.state.rawValue)")
        manager.cancelPeripheralConnection(peripheral)
        note("after cancel: state=\(peripheral.state.rawValue)")
        XCTAssertEqual(peripheral.state, .disconnecting)
        pause(3.0)
        note("events: \(events); final state=\(peripheral.state.rawValue)")

        if peripheral.state != .disconnected {
            disconnect(peripheral)
        }
        XCTAssertEqual(peripheral.state, .disconnected)
    }
}
