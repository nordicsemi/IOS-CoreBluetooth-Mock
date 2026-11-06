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

/// A peripheral manager delegate that records whether each callback was called
/// on the expected queue, and responds to ATT requests.
private final class QueueCheckingDelegate: NSObject, CBMPeripheralManagerDelegate {
    private let isOnQueue: () -> Bool
    private var expectations: [String: XCTestExpectation] = [:]
    /// Names of callbacks that were not called on the expected queue.
    private(set) var wrongQueue: [String] = []

    init(isOnQueue: @escaping () -> Bool) {
        self.isOnQueue = isOnQueue
    }

    /// Returns an expectation fulfilled when the given callback is called.
    func expect(_ name: String) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: name)
        expectations[name] = expectation
        return expectation
    }

    private func called(_ name: String) {
        if !isOnQueue() {
            wrongQueue.append(name)
        }
        expectations[name]?.fulfill()
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBMPeripheralManager) {
        called("didUpdateState")
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBMPeripheralManager, error: Error?) {
        called("didStartAdvertising")
    }

    func peripheralManager(_ peripheral: CBMPeripheralManager, didAdd service: CBMService, error: Error?) {
        called("didAdd")
    }

    func peripheralManager(_ peripheral: CBMPeripheralManager, central: CBMCentral,
                           didSubscribeTo characteristic: CBMCharacteristic) {
        called("didSubscribeTo")
    }

    func peripheralManager(_ peripheral: CBMPeripheralManager, central: CBMCentral,
                           didUnsubscribeFrom characteristic: CBMCharacteristic) {
        called("didUnsubscribeFrom")
    }

    func peripheralManager(_ peripheral: CBMPeripheralManager, didReceiveRead request: CBMATTRequest) {
        called("didReceiveRead")
        request.value = Data([0x01])
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBMPeripheralManager, didReceiveWrite requests: [CBMATTRequest]) {
        called("didReceiveWrite")
        if let first = requests.first {
            peripheral.respond(to: first, withResult: .success)
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBMPeripheralManager) {
        called("isReadyToUpdateSubscribers")
    }

    @available(iOS 11.0, *)
    func peripheralManager(_ peripheral: CBMPeripheralManager,
                           didPublishL2CAPChannel PSM: CBML2CAPPSM, error: Error?) {
        called("didPublishL2CAPChannel")
    }

    @available(iOS 11.0, *)
    func peripheralManager(_ peripheral: CBMPeripheralManager,
                           didUnpublishL2CAPChannel PSM: CBML2CAPPSM, error: Error?) {
        called("didUnpublishL2CAPChannel")
    }
}

/// Tests that the peripheral manager delegate callbacks are delivered on the queue given
/// to the manager, as the native `CBPeripheralManager` does.
class PeripheralManagerDelegateQueueTest: XCTestCase {
    private let queueKey = DispatchSpecificKey<String>()
    private let queueLabel = "peripheral-manager-delegate-queue-test"
    private var queue: DispatchQueue!
    private var delegate: QueueCheckingDelegate!
    private var manager: CBMPeripheralManagerMock!
    private var central: CBMCentralSpec!
    private var characteristic: CBMMutableCharacteristic!

    override func setUpWithError() throws {
        queue = DispatchQueue(label: queueLabel)
        queue.setSpecific(key: queueKey, value: queueLabel)
        let key = queueKey
        let label = queueLabel
        delegate = QueueCheckingDelegate { DispatchQueue.getSpecific(key: key) == label }
        central = CBMCentralSpec(connectionInterval: 0.01)
        characteristic = CBMMutableCharacteristic(
            type: CBMUUID(string: "AA01"),
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable])
        let service = CBMMutableService(type: CBMUUID(string: "1111"), primary: true)
        service.characteristics = [characteristic]

        CBMCentralManagerMock.simulateInitialState(.poweredOn)
        let ready = delegate.expect("didUpdateState")
        manager = CBMPeripheralManagerMock(delegate: delegate, queue: queue)
        wait(for: [ready], timeout: 2)

        let added = delegate.expect("didAdd")
        manager.add(service)
        wait(for: [added], timeout: 2)
    }

    override func tearDownWithError() throws {
        CBMCentralManagerMock.simulatePowerOff()
        CBMPeripheralManagerMock.tearDown()
        if #available(iOS 13.0, *) {
            CBMCentralManagerMock.simulateAuthorization(.allowedAlways)
        }
        manager = nil
        central = nil
        queue = nil
    }

    private func assertAllOnQueue(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(delegate.wrongQueue, [], "Callbacks not called on the manager's queue",
                       file: file, line: line)
    }

    func testStateCallbackIsDeliveredOnQueue() {
        let changed = delegate.expect("didUpdateState")
        CBMCentralManagerMock.simulatePowerOff()
        wait(for: [changed], timeout: 2)
        assertAllOnQueue()
    }

    func testAdvertisingCallbackIsDeliveredOnQueue() {
        let started = delegate.expect("didStartAdvertising")
        manager.startAdvertising([CBMAdvertisementDataLocalNameKey: "Name"])
        wait(for: [started], timeout: 2)
        assertAllOnQueue()
    }

    func testSubscriptionCallbacksAreDeliveredOnQueue() {
        central.simulateConnection()
        let subscribed = delegate.expect("didSubscribeTo")
        central.simulateSubscription(to: characteristic)
        wait(for: [subscribed], timeout: 2)

        let unsubscribed = delegate.expect("didUnsubscribeFrom")
        central.simulateUnsubscription(from: characteristic)
        wait(for: [unsubscribed], timeout: 2)
        assertAllOnQueue()
    }

    func testRequestCallbacksAreDeliveredOnQueue() {
        central.simulateConnection()
        let read = delegate.expect("didReceiveRead")
        central.simulateReadRequest(for: characteristic) { _ in }
        wait(for: [read], timeout: 2)

        let write = delegate.expect("didReceiveWrite")
        central.simulateWriteRequest(Data([0x02]), for: characteristic) { _ in }
        wait(for: [write], timeout: 2)
        assertAllOnQueue()
    }

    func testReadyToUpdateSubscribersIsDeliveredOnQueue() {
        central.simulateConnection()
        let subscribed = delegate.expect("didSubscribeTo")
        central.simulateSubscription(to: characteristic)
        wait(for: [subscribed], timeout: 2)

        let ready = delegate.expect("isReadyToUpdateSubscribers")
        XCTAssertTrue(manager.updateValue(Data([0x01]), for: characteristic, onSubscribedCentrals: nil))
        // The transmit queue is full now.
        XCTAssertFalse(manager.updateValue(Data([0x02]), for: characteristic, onSubscribedCentrals: nil))
        wait(for: [ready], timeout: 2)
        assertAllOnQueue()
    }

    func testL2CAPCallbacksAreDeliveredOnQueue() throws {
        guard #available(iOS 11.0, *) else { throw XCTSkip("Requires iOS 11") }
        let published = delegate.expect("didPublishL2CAPChannel")
        manager.publishL2CAPChannel(withEncryption: false)
        wait(for: [published], timeout: 2)

        let unpublished = delegate.expect("didUnpublishL2CAPChannel")
        manager.unpublishL2CAPChannel(0x80)
        wait(for: [unpublished], timeout: 2)
        assertAllOnQueue()
    }
}
