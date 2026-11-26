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

/// Tests that the simulation can be reconfigured from a background thread
/// while advertising timers are firing on the main thread.
class BackgroundSimulationTest: CentralBehaviorTestCase {

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        CBMCentralManagerMock.tearDownSimulation()
    }

    private func makeSpecs(count: Int) -> [CBMPeripheralSpec] {
        (0..<count).map { _ in
            CBMPeripheralSpec
                .simulatePeripheral(proximity: .immediate)
                .advertising(
                    advertisementData: [
                        CBMAdvertisementDataLocalNameKey: "Background",
                        CBMAdvertisementDataIsConnectable: true as NSNumber
                    ],
                    withInterval: 0.001)
                .build()
        }
    }

    func testStoppingAdvertisingOffMainThread_doesNotCrashWhileTimersFire() {
        let finished = expectation(description: "Background work finished")
        let queue = DispatchQueue(label: "background-simulation-test")
        queue.async {
            for _ in 0..<300 {
                CBMCentralManagerMock.simulatePeripherals(self.makeSpecs(count: 5))
                usleep(1_000)
                CBMCentralManagerMock.tearDownSimulation()
                usleep(1_000)
            }
            finished.fulfill()
        }
        // The main run loop keeps firing the advertising timers meanwhile.
        wait(for: [finished], timeout: 60)
    }

    func testAdvertisementStoppedOffMainThread_isNotDiscoveredAfterwards() throws {
        device = TestDevice(advertisingInterval: 0.001)
        CBMCentralManagerMock.simulatePeripherals([device.spec])
        CBMCentralManagerMock.simulateInitialState(.poweredOn)
        waitFor("Manager ready") { ready in
            managerDelegate.didUpdateState = { _ in ready.fulfill() }
            manager = CBMCentralManagerMock(delegate: managerDelegate, queue: nil)
        }
        waitFor("Device discovered") { discovered in
            discovered.assertForOverFulfill = false
            managerDelegate.didDiscoverPeripheral = { _, _, _, _ in discovered.fulfill() }
            manager.scanForPeripherals(withServices: nil,
                                       options: [CBMCentralManagerScanOptionAllowDuplicatesKey: true])
        }
        managerDelegate.didDiscoverPeripheral = nil

        let spec: CBMPeripheralSpec = device.spec
        let advertisement = try XCTUnwrap(spec.advertisement)
        let finished = expectation(description: "Background work finished")
        DispatchQueue(label: "background-advertisement-test").async {
            for _ in 0..<100 {
                spec.simulateAdvertisementChange(advertisement)
                usleep(1_000)
                spec.simulateAdvertisementChange(nil)
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 60)

        // Discoveries notified before advertising stopped may still be queued on the main queue.
        pause(0.1)
        waitFor("No discovery after advertising stopped", timeout: 0.2, inverted: true) { discovered in
            managerDelegate.didDiscoverPeripheral = { _, _, _, _ in discovered.fulfill() }
        }
    }
}
