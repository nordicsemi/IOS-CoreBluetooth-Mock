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

/// Tests of the central manager: state, scanning and connection management.
///
/// Expectations in these tests follow the behavior of the native `CBCentralManager`.
class CentralManagerBehaviorTest: CentralBehaviorTestCase {

    // MARK: - State

    func testStateIsUnknownUntilInitialized() {
        device = TestDevice()
        CBMCentralManagerMock.simulatePeripherals([device.spec])
        CBMCentralManagerMock.simulateInitialState(.poweredOn)

        var statesReported = 0
        waitFor("State reported") { reported in
            managerDelegate.didUpdateState = { _ in
                statesReported += 1
                reported.fulfill()
            }
            manager = CBMCentralManagerMock(delegate: managerDelegate, queue: nil)
            // The state is reported asynchronously, as in the native implementation.
            XCTAssertEqual(manager.state, .unknown)
        }
        XCTAssertEqual(manager.state, .poweredOn)
        XCTAssertEqual(statesReported, 1)
    }

    func testPowerCycleNotifiesDelegate() {
        setUpManager()
        var states: [CBMManagerState] = []
        managerDelegate.didUpdateState = { states.append($0.state) }

        CBMCentralManagerMock.simulatePowerOff()
        pause(0.1)
        CBMCentralManagerMock.simulatePowerOn()
        pause(0.1)

        XCTAssertEqual(states, [.poweredOff, .poweredOn])
        XCTAssertEqual(manager.state, .poweredOn)
    }

    func testRepeatedPowerOnDoesNotNotify() {
        setUpManager()
        managerDelegate.didUpdateState = { _ in XCTFail("State did not change") }

        CBMCentralManagerMock.simulatePowerOn()
        pause(0.1)
    }

    func testInitialPoweredOffState() {
        setUpManager(initialState: .poweredOff)
        XCTAssertEqual(manager.state, .poweredOff)
    }

    func testUnauthorizedState() throws {
        guard #available(iOS 13.0, *) else { throw XCTSkip("Requires iOS 13") }
        setUpManager()

        waitFor("Delegate notified") { notified in
            managerDelegate.didUpdateState = { _ in notified.fulfill() }
            CBMCentralManagerMock.simulateAuthorization(.denied)
        }
        XCTAssertEqual(manager.state, .unauthorized)
        XCTAssertEqual(manager.authorization, .denied)
    }

    // MARK: - Scanning

    func testScanIgnoredWhenPoweredOff() {
        setUpManager(initialState: .poweredOff)
        manager.scanForPeripherals(withServices: nil)
        XCTAssertFalse(manager.isScanning)
    }

    func testScanningFlag() {
        setUpManager()
        XCTAssertFalse(manager.isScanning)
        manager.scanForPeripherals(withServices: nil)
        XCTAssertTrue(manager.isScanning)
        manager.stopScan()
        XCTAssertFalse(manager.isScanning)
    }

    func testPowerOffStopsScanning() {
        setUpManager()
        manager.scanForPeripherals(withServices: nil)

        CBMCentralManagerMock.simulatePowerOff()
        pause(0.1)

        XCTAssertFalse(manager.isScanning)
    }

    func testDeviceIsDiscovered() {
        setUpManager()

        var advertisement: [String : Any]?
        var rssi: Int?
        var discovered: CBMPeripheral?
        waitFor("Device discovered") { found in
            managerDelegate.didDiscoverPeripheral = { _, peripheral, data, RSSI in
                discovered = peripheral
                advertisement = data
                rssi = RSSI.intValue
                found.fulfill()
            }
            manager.scanForPeripherals(withServices: nil)
        }

        XCTAssertEqual(discovered?.identifier, device.identifier)
        XCTAssertEqual(discovered?.name, TestDevice.name)
        XCTAssertEqual(discovered?.state, .disconnected)
        XCTAssertEqual(advertisement?[CBMAdvertisementDataLocalNameKey] as? String, TestDevice.name)
        XCTAssertEqual(advertisement?[CBMAdvertisementDataServiceUUIDsKey] as? [CBMUUID], [TestDevice.serviceA])
        XCTAssertEqual((advertisement?[CBMAdvertisementDataIsConnectable] as? NSNumber)?.boolValue, true)
        // Without deviation the RSSI is the one defined by the proximity.
        XCTAssertEqual(rssi, -40)
    }

    func testRSSIDependsOnProximity() {
        setUpManager(proximity: .far)

        var rssi: Int?
        waitFor("Device discovered") { found in
            managerDelegate.didDiscoverPeripheral = { _, _, _, RSSI in
                rssi = RSSI.intValue
                found.fulfill()
            }
            manager.scanForPeripherals(withServices: nil)
        }
        XCTAssertEqual(rssi, -100)
    }

    func testRSSIDeviation() {
        CBMCentralManagerMock.simulateRSSIDeviation(.custom(5))
        setUpManager()

        var values: [Int] = []
        managerDelegate.didDiscoverPeripheral = { _, _, _, RSSI in
            values.append(RSSI.intValue)
        }
        manager.scanForPeripherals(withServices: nil,
                                   options: [CBMCentralManagerScanOptionAllowDuplicatesKey: true])
        pause(0.5)

        XCTAssertFalse(values.isEmpty)
        XCTAssertTrue(values.allSatisfy { (-45...(-35)).contains($0) }, "RSSI values: \(values)")
    }

    func testScanFilterMatchingService() {
        setUpManager()
        waitFor("Device discovered") { found in
            managerDelegate.didDiscoverPeripheral = { _, _, _, _ in found.fulfill() }
            manager.scanForPeripherals(withServices: [TestDevice.serviceA])
        }
    }

    func testScanFilterNotMatchingService() {
        setUpManager()
        waitFor("Device not discovered", timeout: 0.5, inverted: true) { found in
            managerDelegate.didDiscoverPeripheral = { _, _, _, _ in found.fulfill() }
            manager.scanForPeripherals(withServices: [TestDevice.serviceB])
        }
    }

    func testOutOfRangeDeviceIsNotDiscovered() {
        setUpManager(proximity: .outOfRange)
        waitFor("Device not discovered", timeout: 0.5, inverted: true) { found in
            managerDelegate.didDiscoverPeripheral = { _, _, _, _ in found.fulfill() }
            manager.scanForPeripherals(withServices: nil)
        }
    }

    func testDevicesAreReportedOnceByDefault() {
        setUpManager()

        var count = 0
        managerDelegate.didDiscoverPeripheral = { _, _, _, _ in count += 1 }
        manager.scanForPeripherals(withServices: nil)
        pause(0.5)

        XCTAssertEqual(count, 1)
    }

    func testDevicesAreReportedRepeatedlyWhenDuplicatesAllowed() {
        setUpManager()

        var count = 0
        managerDelegate.didDiscoverPeripheral = { _, _, _, _ in count += 1 }
        manager.scanForPeripherals(withServices: nil,
                                   options: [CBMCentralManagerScanOptionAllowDuplicatesKey: true])
        pause(0.5)

        XCTAssertGreaterThan(count, 2)
    }

    func testStopScanStopsReporting() {
        setUpManager()
        waitFor("Device discovered") { found in
            managerDelegate.didDiscoverPeripheral = { _, _, _, _ in found.fulfill() }
            manager.scanForPeripherals(withServices: nil,
                                       options: [CBMCentralManagerScanOptionAllowDuplicatesKey: true])
        }
        manager.stopScan()

        waitFor("No more reports", timeout: 0.3, inverted: true) { found in
            managerDelegate.didDiscoverPeripheral = { _, _, _, _ in found.fulfill() }
        }
    }

    func testRestartedScanReportsDeviceAgain() {
        setUpManager()
        waitFor("Device discovered") { found in
            managerDelegate.didDiscoverPeripheral = { _, _, _, _ in found.fulfill() }
            manager.scanForPeripherals(withServices: nil)
        }
        manager.stopScan()

        waitFor("Device discovered again") { found in
            managerDelegate.didDiscoverPeripheral = { _, _, _, _ in found.fulfill() }
            manager.scanForPeripherals(withServices: nil)
        }
    }

    // MARK: - Connecting

    func testConnect() throws {
        setUpManager()
        let peripheral = try retrieveDevice()
        XCTAssertEqual(peripheral.state, .disconnected)

        waitFor("Connected") { connected in
            managerDelegate.didConnect = { _, connectedPeripheral in
                XCTAssertTrue(connectedPeripheral === peripheral)
                connected.fulfill()
            }
            manager.connect(peripheral)
            // The state changes immediately.
            XCTAssertEqual(peripheral.state, .connecting)
        }
        XCTAssertEqual(peripheral.state, .connected)
    }

    func testConnectionFailure() throws {
        setUpManager()
        let error = CBMError(.connectionFailed)
        device.connectionResult = .failure(error)
        let peripheral = try retrieveDevice()

        waitFor("Connection failed") { failed in
            managerDelegate.didConnect = { _, _ in XCTFail("Should not connect") }
            managerDelegate.didFailToConnect = { _, failedPeripheral, receivedError in
                XCTAssertTrue(failedPeripheral === peripheral)
                XCTAssertEqual((receivedError as? CBMError)?.code, .connectionFailed)
                failed.fulfill()
            }
            manager.connect(peripheral)
        }
        XCTAssertEqual(peripheral.state, .disconnected)
    }

    func testConnectIgnoredWhenPoweredOff() throws {
        setUpManager()
        let peripheral = try retrieveDevice()
        CBMCentralManagerMock.simulatePowerOff()
        pause(0.1)

        waitFor("Not connected", timeout: 0.3, inverted: true) { connected in
            managerDelegate.didConnect = { _, _ in connected.fulfill() }
            manager.connect(peripheral)
        }
        XCTAssertNotEqual(peripheral.state, .connected)
    }

    func testPendingConnectionCompletesWhenDeviceComesInRange() throws {
        setUpManager(proximity: .outOfRange)
        let peripheral = try retrieveDevice()

        // There is no timeout for pending connection.
        waitFor("Not connected", timeout: 0.3, inverted: true) { connected in
            managerDelegate.didConnect = { _, _ in connected.fulfill() }
            manager.connect(peripheral)
        }
        XCTAssertEqual(peripheral.state, .connecting)

        waitFor("Connected") { connected in
            managerDelegate.didConnect = { _, _ in connected.fulfill() }
            // The device starts to be seen on the next advertising packet.
            device.spec.simulateProximityChange(.near)
        }
        XCTAssertEqual(peripheral.state, .connected)
    }

    func testCancellingPendingConnection() throws {
        setUpManager(proximity: .outOfRange)
        let peripheral = try retrieveDevice()
        manager.connect(peripheral)
        XCTAssertEqual(peripheral.state, .connecting)

        waitFor("Disconnected") { disconnected in
            managerDelegate.didDisconnect = { _, _, _, _, _ in disconnected.fulfill() }
            manager.cancelPeripheralConnection(peripheral)
            XCTAssertEqual(peripheral.state, .disconnecting)
        }
        XCTAssertEqual(peripheral.state, .disconnected)

        // Coming in range does not connect the device anymore.
        waitFor("Not connected", timeout: 0.5, inverted: true) { connected in
            managerDelegate.didConnect = { _, _ in connected.fulfill() }
            device.spec.simulateProximityChange(.near)
        }
        XCTAssertEqual(peripheral.state, .disconnected)
    }

    func testCancellingPendingConnectionReportsDisconnection() throws {
        // The documentation of `cancelPeripheralConnection(_:)` covers active and pending
        // connections, and the central manager reports the peripheral as disconnected.
        // This has not been verified on a physical device.
        setUpManager(proximity: .outOfRange)
        let peripheral = try retrieveDevice()
        manager.connect(peripheral)

        waitFor("Disconnected") { disconnected in
            managerDelegate.didDisconnect = { _, disconnectedPeripheral, _, isReconnecting, error in
                XCTAssertTrue(disconnectedPeripheral === peripheral)
                XCTAssertFalse(isReconnecting)
                XCTAssertNil(error)
                disconnected.fulfill()
            }
            manager.cancelPeripheralConnection(peripheral)
        }
        XCTAssertEqual(peripheral.state, .disconnected)
        // The device never connected, so it is not notified.
        XCTAssertEqual(device.disconnections, 0)
    }

    func testCancellingConnectionTwiceReportsOnce() throws {
        setUpManager()
        let peripheral = try connectToDevice()

        var reports = 0
        managerDelegate.didDisconnect = { _, _, _, _, _ in reports += 1 }
        manager.cancelPeripheralConnection(peripheral)
        manager.cancelPeripheralConnection(peripheral)
        pause(0.3)

        XCTAssertEqual(reports, 1)
        XCTAssertEqual(peripheral.state, .disconnected)
    }

    func testCancellingAutoReconnect() throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { throw XCTSkip("Requires iOS 17") }
        setUpManager()
        let peripheral = try retrieveDevice()
        waitFor("Connected") { connected in
            managerDelegate.didConnect = { _, _ in connected.fulfill() }
            manager.connect(peripheral, options: [CBMConnectPeripheralOptionEnableAutoReconnect: true])
        }

        // The device disconnects, and the central starts reconnecting.
        waitFor("Disconnected, reconnecting", timeout: 6.0) { disconnected in
            managerDelegate.didDisconnect = { _, _, _, isReconnecting, error in
                XCTAssertTrue(isReconnecting)
                XCTAssertNotNil(error)
                disconnected.fulfill()
            }
            // Out of range, so that the reconnection stays pending.
            device.spec.simulateProximityChange(.outOfRange)
        }
        XCTAssertEqual(peripheral.state, .connecting)

        // Cancelling stops the reconnection.
        waitFor("Disconnected") { disconnected in
            managerDelegate.didDisconnect = { _, _, _, isReconnecting, error in
                XCTAssertFalse(isReconnecting)
                XCTAssertNil(error)
                disconnected.fulfill()
            }
            manager.cancelPeripheralConnection(peripheral)
        }
        XCTAssertEqual(peripheral.state, .disconnected)

        waitFor("Not reconnected", timeout: 0.5, inverted: true) { connected in
            managerDelegate.didConnect = { _, _ in connected.fulfill() }
            device.spec.simulateProximityChange(.near)
        }
        XCTAssertEqual(peripheral.state, .disconnected)
    }

    func testCancellingConnection() throws {
        setUpManager()
        let peripheral = try connectToDevice()

        waitFor("Disconnected") { disconnected in
            managerDelegate.didDisconnect = { _, disconnectedPeripheral, _, _, error in
                XCTAssertTrue(disconnectedPeripheral === peripheral)
                // Disconnection requested by the app does not report an error.
                XCTAssertNil(error)
                disconnected.fulfill()
            }
            manager.cancelPeripheralConnection(peripheral)
            XCTAssertEqual(peripheral.state, .disconnecting)
        }
        XCTAssertEqual(peripheral.state, .disconnected)
        XCTAssertEqual(device.disconnections, 1)
    }

    func testCancellingDisconnectedPeripheralDoesNothing() throws {
        setUpManager()
        let peripheral = try retrieveDevice()

        waitFor("Nothing reported", timeout: 0.3, inverted: true) { reported in
            managerDelegate.didDisconnect = { _, _, _, _, _ in reported.fulfill() }
            manager.cancelPeripheralConnection(peripheral)
        }
        XCTAssertEqual(peripheral.state, .disconnected)
    }

    func testDeviceInitiatedDisconnection() throws {
        setUpManager()
        let peripheral = try connectToDevice()

        waitFor("Disconnected") { disconnected in
            managerDelegate.didDisconnect = { _, _, _, isReconnecting, error in
                XCTAssertFalse(isReconnecting)
                XCTAssertEqual((error as? CBMError)?.code, .peripheralDisconnected)
                disconnected.fulfill()
            }
            device.spec.simulateDisconnection()
        }
        XCTAssertEqual(peripheral.state, .disconnected)
    }

    func testServicesAreInvalidatedOnDisconnection() throws {
        setUpManager()
        let peripheral = try connectAndDiscover()
        XCTAssertNotNil(peripheral.services)

        waitFor("Disconnected") { disconnected in
            managerDelegate.didDisconnect = { _, _, _, _, _ in disconnected.fulfill() }
            device.spec.simulateDisconnection()
        }
        XCTAssertNil(peripheral.services)
    }

    func testReconnection() throws {
        setUpManager()
        let peripheral = try connectToDevice()
        waitFor("Disconnected") { disconnected in
            managerDelegate.didDisconnect = { _, _, _, _, _ in disconnected.fulfill() }
            manager.cancelPeripheralConnection(peripheral)
        }

        waitFor("Connected again") { connected in
            managerDelegate.didConnect = { _, _ in connected.fulfill() }
            manager.connect(peripheral)
        }
        XCTAssertEqual(peripheral.state, .connected)
    }

    func testMovingOutOfRangeDisconnectsWithTimeout() throws {
        setUpManager()
        let peripheral = try connectToDevice()

        waitFor("Disconnected", timeout: 6.0) { disconnected in
            managerDelegate.didDisconnect = { _, _, _, _, error in
                XCTAssertEqual((error as? CBMError)?.code, .connectionTimeout)
                disconnected.fulfill()
            }
            device.spec.simulateProximityChange(.outOfRange)
        }
        XCTAssertEqual(peripheral.state, .disconnected)
    }

    func testPowerOffDisconnectsPeripherals() throws {
        setUpManager()
        let peripheral = try connectToDevice()

        CBMCentralManagerMock.simulatePowerOff()
        pause(0.1)

        XCTAssertEqual(peripheral.state, .disconnected)
        XCTAssertNil(peripheral.services)
    }

    // MARK: - Retrieving

    func testRetrieveUnknownPeripheral() {
        setUpManager()
        XCTAssertTrue(manager.retrievePeripherals(withIdentifiers: [UUID()]).isEmpty)
    }

    func testRetrieveReturnsEmptyListWhenPoweredOff() {
        setUpManager(initialState: .poweredOff)
        XCTAssertTrue(manager.retrievePeripherals(withIdentifiers: [device.identifier]).isEmpty)
        XCTAssertTrue(manager.retrieveConnectedPeripherals(withServices: [TestDevice.serviceA]).isEmpty)
    }

    func testRetrieveConnectedPeripherals() throws {
        setUpManager()
        XCTAssertTrue(manager.retrieveConnectedPeripherals(withServices: [TestDevice.serviceA]).isEmpty)

        let peripheral = try connectAndDiscover()
        let connected = manager.retrieveConnectedPeripherals(withServices: [TestDevice.serviceA])
        XCTAssertEqual(connected.count, 1)
        XCTAssertTrue(connected.first === peripheral)

        // The device does not have this service.
        XCTAssertTrue(manager.retrieveConnectedPeripherals(withServices: [CBMUUID(string: "3333")]).isEmpty)
    }
}
