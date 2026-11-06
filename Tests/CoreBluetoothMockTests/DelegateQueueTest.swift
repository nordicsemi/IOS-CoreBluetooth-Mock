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

/// Tests that delegate callbacks are delivered on the queue given to the central manager,
/// as the native `CBCentralManager` does.
class DelegateQueueTest: CentralBehaviorTestCase {
    private let queueKey = DispatchSpecificKey<String>()
    private let queueLabel = "delegate-queue-test"
    private var queue: DispatchQueue!

    override func setUpWithError() throws {
        try super.setUpWithError()
        queue = DispatchQueue(label: queueLabel)
        queue.setSpecific(key: queueKey, value: queueLabel)
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        queue = nil
    }

    private var isOnQueue: Bool {
        DispatchQueue.getSpecific(key: queueKey) == queueLabel
    }

    private func assertOnQueue(_ callback: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(isOnQueue, "\(callback) was not called on the manager's queue", file: file, line: line)
    }

    /// Creates the manager using the custom queue.
    private func setUpManagerWithQueue() {
        device = TestDevice()
        CBMCentralManagerMock.simulatePeripherals([device.spec])
        CBMCentralManagerMock.simulateInitialState(.poweredOn)
        waitFor("Manager ready") { ready in
            managerDelegate.didUpdateState = { [unowned self] _ in
                assertOnQueue("centralManagerDidUpdateState")
                ready.fulfill()
            }
            manager = CBMCentralManagerMock(delegate: managerDelegate, queue: queue)
        }
        managerDelegate.didUpdateState = nil
    }

    // MARK: - Central manager delegate

    func testStateUpdatesAreDeliveredOnQueue() {
        setUpManagerWithQueue()
        waitFor("Powered off") { off in
            managerDelegate.didUpdateState = { [unowned self] _ in
                assertOnQueue("centralManagerDidUpdateState")
                off.fulfill()
            }
            CBMCentralManagerMock.simulatePowerOff()
        }
        managerDelegate.didUpdateState = nil
    }

    func testDiscoveryIsDeliveredOnQueue() {
        setUpManagerWithQueue()
        waitFor("Discovered") { discovered in
            managerDelegate.didDiscoverPeripheral = { [unowned self] _, _, _, _ in
                assertOnQueue("centralManager(_:didDiscover:advertisementData:rssi:)")
                discovered.fulfill()
            }
            manager.scanForPeripherals(withServices: nil)
        }
        manager.stopScan()
    }

    func testConnectionCallbacksAreDeliveredOnQueue() throws {
        setUpManagerWithQueue()
        let peripheral = try retrieveDevice()
        waitFor("Connected") { connected in
            managerDelegate.didConnect = { [unowned self] _, _ in
                assertOnQueue("centralManager(_:didConnect:)")
                connected.fulfill()
            }
            manager.connect(peripheral)
        }
        waitFor("Disconnected") { disconnected in
            managerDelegate.didDisconnect = { [unowned self] _, _, _, _, _ in
                assertOnQueue("centralManager(_:didDisconnectPeripheral:...)")
                disconnected.fulfill()
            }
            manager.cancelPeripheralConnection(peripheral)
        }
    }

    func testFailedConnectionIsDeliveredOnQueue() throws {
        setUpManagerWithQueue()
        device.connectionResult = .failure(CBMError(.connectionFailed))
        let peripheral = try retrieveDevice()
        waitFor("Failed") { failed in
            managerDelegate.didFailToConnect = { [unowned self] _, _, _ in
                assertOnQueue("centralManager(_:didFailToConnect:error:)")
                failed.fulfill()
            }
            manager.connect(peripheral)
        }
    }

    // MARK: - Peripheral delegate

    /// Connects and discovers everything, checking the queue of each callback.
    private func connectAndDiscoverOnQueue() throws -> CBMPeripheral {
        setUpManagerWithQueue()
        let peripheral = try retrieveDevice()
        peripheral.delegate = peripheralDelegate
        waitFor("Connected") { connected in
            managerDelegate.didConnect = { _, _ in connected.fulfill() }
            manager.connect(peripheral)
        }
        waitFor("Services discovered") { discovered in
            peripheralDelegate.didDiscoverServices = { [unowned self] _, _ in
                assertOnQueue("peripheral(_:didDiscoverServices:)")
                discovered.fulfill()
            }
            peripheral.discoverServices(nil)
        }
        let service = try XCTUnwrap(peripheral.services?.first { $0.uuid == TestDevice.serviceA })
        waitFor("Characteristics discovered") { discovered in
            peripheralDelegate.didDiscoverCharacteristics = { [unowned self] _, _, _ in
                assertOnQueue("peripheral(_:didDiscoverCharacteristicsFor:error:)")
                discovered.fulfill()
            }
            peripheral.discoverCharacteristics(nil, for: service)
        }
        let readCharacteristic = try characteristic(TestDevice.readChar, of: peripheral)
        waitFor("Descriptors discovered") { discovered in
            peripheralDelegate.didDiscoverDescriptors = { [unowned self] _, _, _ in
                assertOnQueue("peripheral(_:didDiscoverDescriptorsFor:error:)")
                discovered.fulfill()
            }
            peripheral.discoverDescriptors(for: readCharacteristic)
        }
        return peripheral
    }

    func testDiscoveryCallbacksAreDeliveredOnQueue() throws {
        _ = try connectAndDiscoverOnQueue()
    }

    func testReadWriteAndNotificationCallbacksAreDeliveredOnQueue() throws {
        let peripheral = try connectAndDiscoverOnQueue()

        let readChar = try characteristic(TestDevice.readChar, of: peripheral)
        waitFor("Read") { read in
            peripheralDelegate.didUpdateCharacteristicValue = { [unowned self] _, _, _ in
                assertOnQueue("peripheral(_:didUpdateValueFor:error:)")
                read.fulfill()
            }
            peripheral.readValue(for: readChar)
        }

        let writeChar = try characteristic(TestDevice.writeChar, of: peripheral)
        waitFor("Written") { written in
            peripheralDelegate.didWriteCharacteristicValue = { [unowned self] _, _, _ in
                assertOnQueue("peripheral(_:didWriteValueFor:error:)")
                written.fulfill()
            }
            peripheral.writeValue(Data([0x01]), for: writeChar, type: .withResponse)
        }

        let descriptor = try XCTUnwrap(readChar.descriptors?.first)
        waitFor("Descriptor read") { read in
            peripheralDelegate.didUpdateDescriptorValue = { [unowned self] _, _, _ in
                assertOnQueue("peripheral(_:didUpdateValueFor descriptor:error:)")
                read.fulfill()
            }
            peripheral.readValue(for: descriptor)
        }

        let notifyChar = try characteristic(TestDevice.notifyChar, of: peripheral)
        waitFor("Notifications enabled") { enabled in
            peripheralDelegate.didUpdateNotificationState = { [unowned self] _, _, _ in
                assertOnQueue("peripheral(_:didUpdateNotificationStateFor:error:)")
                enabled.fulfill()
            }
            peripheral.setNotifyValue(true, for: notifyChar)
        }

        waitFor("Notification received") { received in
            peripheralDelegate.didUpdateCharacteristicValue = { [unowned self] _, _, _ in
                assertOnQueue("peripheral(_:didUpdateValueFor:error:) for notification")
                received.fulfill()
            }
            device.spec.simulateValueUpdate(Data([0x07]), for: device.notifyCharacteristic)
        }
    }

    func testRSSIAndNameCallbacksAreDeliveredOnQueue() throws {
        let peripheral = try connectAndDiscoverOnQueue()
        waitFor("RSSI read") { read in
            peripheralDelegate.didReadRSSI = { [unowned self] _, _, _ in
                assertOnQueue("peripheral(_:didReadRSSI:error:)")
                read.fulfill()
            }
            peripheral.readRSSI()
        }
        let nameUpdated = expectation(description: "Name updated")
        let modified = expectation(description: "Services modified")
        peripheralDelegate.didUpdateName = { [unowned self] _ in
            assertOnQueue("peripheralDidUpdateName(_:)")
            nameUpdated.fulfill()
        }
        peripheralDelegate.didModifyServices = { [unowned self] _, _ in
            assertOnQueue("peripheral(_:didModifyServices:)")
            modified.fulfill()
        }
        let remaining = device.spec.services?.filter { $0.uuid == TestDevice.serviceA } ?? []
        device.spec.simulateServiceChange(newName: "New name", newServices: remaining)
        wait(for: [nameUpdated, modified], timeout: 2)
    }

    func testReadyToSendWriteWithoutResponseIsDeliveredOnQueue() throws {
        let peripheral = try connectAndDiscoverOnQueue()
        let writeChar = try characteristic(TestDevice.writeChar, of: peripheral)
        waitFor("Ready") { ready in
            peripheralDelegate.isReadyToSendWriteWithoutResponse = { [unowned self] _ in
                assertOnQueue("peripheralIsReady(toSendWriteWithoutResponse:)")
                ready.fulfill()
            }
            for _ in 0..<5 where peripheral.canSendWriteWithoutResponse {
                peripheral.writeValue(Data([0x01]), for: writeChar, type: .withoutResponse)
            }
        }
    }
}
