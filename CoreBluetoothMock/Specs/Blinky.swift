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

import Foundation
import Combine

// MARK: - Blinky

/// A delegate protocol for receiving updates from the `Blinky` peripheral.
public protocol BlinkyDelegate: AnyObject {
    
    /// Notifies the delegate that the connected central requested LED state change on the specified Blinky peripheral.
    ///
    /// - Parameters:
    ///   - blinky: The `Blinky` instance.
    ///   - isOn: A Boolean value indicating the new state of the LED. `true` if the LED is on; otherwise, `false`.
    func blinky(_ blinky: Blinky, didChangeLedState isOn: Bool)
    
    /// Notifies the delegate that the subscription state for the button characteristic has changed.
    ///
    /// - Parameters:
    ///   - blinky: The `Blinky` instance.
    ///   - isSubscribed: A Boolean value indicating whether a client is now subscribed to button state changes.
    func blinky(_ blinky: Blinky, didChangeButtonSubscriptionState isSubscribed: Bool)
}

/// A sample ``BlinkyDelegate`` that will periodically simulate button presses when a client is
/// subscribed to button notifications.
public class PeriodicBlinkyDelegate: BlinkyDelegate {
    /// The timer used to schedule periodic simulated button presses. Kept `nil` when not active.
    private var timer: DispatchSourceTimer?

    /// An period of time between simulated button presses.
    ///
    /// Defaults to 1 second.
    private let period: TimeInterval
    /// The time the button will be in *pressed* state.
    private let pressedDuration: TimeInterval
    
    /// Creates a periodic, simulated Blinky delegate that will "press" the button at a fixed cadence
    /// whenever a client is subscribed to button notifications.
    ///
    /// - Parameters:
    ///   - releasedDuration: The duration, in seconds, that the simulated button remains in the "released".
    ///                       Defaults to 1 second.
    ///   - pressedDuration: The duration, in seconds, that the simulated button remains in the "pressed"
    ///                      Defaults to 250 ms.
    public init(releasedDuration: TimeInterval = 1.0,
                pressedDuration: TimeInterval = 0.250) {
        self.period = releasedDuration + pressedDuration
        self.pressedDuration = pressedDuration
    }
    
    public func blinky(_ blinky: Blinky, didChangeLedState isOn: Bool) {
        // No Op.
    }
    
    public func blinky(_ blinky: Blinky, didChangeButtonSubscriptionState isSubscribed: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if isSubscribed {
                self.startTimer(for: blinky)
            } else {
                self.stopTimer()
            }
        }
    }
    
    private func startTimer(for blinky: Blinky) {
        // If a timer is already active, do nothing to avoid duplicate schedules.
        guard timer == nil else { return }

        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        // First fire after `period`, then repeat every `period`.
        t.schedule(deadline: .now() + period, repeating: period)
        t.setEventHandler { [weak self, weak blinky] in
            guard let self = self, let blinky = blinky, self.timer != nil else { return }
            // Simulate button press.
            blinky.simulateButtonToggle()
            // Schedule release after pressDuration.
            DispatchQueue.main.asyncAfter(deadline: .now() + self.pressedDuration) { [weak self, weak blinky] in
                guard let self = self, let blinky = blinky, self.timer != nil else { return }
                blinky.simulateButtonToggle()
            }
        }
        self.timer = t
        t.resume()
    }
    
    private func stopTimer() {
        guard let t = timer else { return }
        t.setEventHandler {}
        t.cancel()
        timer = nil
    }
}

/// A sample implementation of a mock peripheral with Nordic LED Button Service (LBS), also known as *Blinky*.
///
/// A connected client can send requests to turn the LED on or OFF, and subscribe to button state notifications.
///
/// The `Blinky` object provides methods to simulate button toggles and peripheral resets, which can be used in tests.
///
/// The instance begins advertising the LED Button Service (UUID 00001523-1212-EFDE-1523-785FEABCD123) as connectable,
/// with a 250 ms advertising interval.
/// When connected, it exposes:
///   - Button characteristic (notify + read): sends notifications on simulated button toggles.
///   - LED characteristic (write + read): accepts writes to change LED state and notifies the delegate.
///
/// Use ``Blinky/simulateButtonToggle()`` to simulate a Button press on the DK, which will send a
/// notification to the connected client, and ``Blinky/simulateReset()`` to simulate a peripheral reset,
/// which will reset the LED state to the initial value and terminate existing connection.
///
/// - seeAlso: ``simulateButtonToggle()``, ``simulateReset()``, ``BlinkyDelegate``
public class Blinky {
    public static let serviceUUID = CBMUUID.ledButtonService
    
    /// The peripheral specification that defines the behavior of this Blinky peripheral.
    public let spec: CBMPeripheralSpec
    
    // MARK: Private Properties
    
    /// The name of the peripheral, used in the advertisement data and as a local name when connected.
    private let name: String
    /// The implementation of the Blinky peripheral's behavior, handling read/write requests and notifications.
    private let impl: BlinkyImpl
    
    // MARK: init
    
    /// Initializes a mock peripheral with Nordic LED Button Service (LBS), also known as *Blinky*.
    ///
    /// - Parameters:
    ///   - identifier: The stable, unique identifier for the simulated peripheral.
    ///                 Provide a fixed value to keep the same identity across app launches (default: a new UUID()).
    ///   - name: The local name used in advertising and when connected. Defaults to "Nordic_Blinky".
    ///   - proximity: The simulated proximity used by CoreBluetoothMock to influence RSSI and discovery behavior.
    ///                Defaults to `.immediate`.
    ///   - delegate: An optional delegate receiving LED state updates and button subscription changes.
    ///               The delegate is not retained.
    ///
    /// - seeAlso: ``PeriodicBlinkyDelegate``
    public init(identifier: UUID = UUID(),
                name: String = "Nordic_Blinky",
                proximity: CBMProximity = .immediate,
                delegate: BlinkyDelegate? = nil) {
        self.name = name
        self.impl = BlinkyImpl()
        self.spec = CBMPeripheralSpec
            .simulatePeripheral(identifier: identifier, proximity: proximity)
            .advertising(
                advertisementData: [
                    CBMAdvertisementDataIsConnectable : true as NSNumber,
                    CBMAdvertisementDataLocalNameKey : name,
                    CBMAdvertisementDataServiceUUIDsKey : [CBMUUID.ledButtonService]
                ],
                withInterval: 0.250, // sec
                delay: 0, // sec
                alsoWhenConnected: false
            )
            .connectable(
                name: name,
                services: [.blinkyService],
                delegate: impl,
                connectionInterval: 0.02,
            )
            .build()
        
        // Handle state changes.
        weak let userDelegate = delegate
        impl.ledStateDidChange = { [weak self, userDelegate] isOn in
            DispatchQueue.main.async { [weak self, userDelegate] in
                guard let self = self else { return }
                userDelegate?.blinky(self, didChangeLedState: isOn)
            }
        }
        impl.buttonSubscriptionStateDidChange = { [weak self, userDelegate] isSubscribed in
            DispatchQueue.main.async { [weak self, userDelegate] in
                guard let self = self else { return }
                userDelegate?.blinky(self, didChangeButtonSubscriptionState: isSubscribed)
            }
        }
    }
    
    /// Simulates a button toggle.
    ///
    /// This will send a notification to the subscribed client.
    public func simulateButtonToggle() {
        impl.isButtonPressed.toggle()
        spec.simulateValueUpdate(impl.isButtonPressed.data, for: .buttonCharacteristic)
    }
    
    /// Simulates a peripheral reset, which will disconnect all connected centrals and stop advertising.
    public func simulateReset() {
        spec.simulateReset()
    }
}

// MARK: - CBMPeripheralSpecDelegate

private class BlinkyImpl: CBMPeripheralSpecDelegate {
    
    // MARK: Properties
    
    var ledStateDidChange: ((Bool) -> ())!
    var buttonSubscriptionStateDidChange: ((Bool) -> ())!
    
    var isLedOn: Bool = false
    var isButtonPressed: Bool = false
    
    // MARK: CBMPeripheralSpecDelegate
    
    public func peripheral(_ peripheral: CBMPeripheralSpec,
                           didReceiveReadRequestFor characteristic: CBMCharacteristicMock) -> Result<Data, Error> {
        switch characteristic.uuid {
        case .buttonCharacteristic:
            return .success(isButtonPressed.data)
        case .ledCharacteristic:
            return .success(isLedOn.data)
        default:
            return .failure(CBMATTError(.readNotPermitted))
        }
    }
    
    public func peripheral(_ peripheral: CBMPeripheralSpec,
                           didReceiveWriteRequestFor characteristic: CBMCharacteristicMock,
                           data: Data) -> Result<Void, Error> {
        switch characteristic.uuid {
        case .ledCharacteristic:
            isLedOn = data.bool
            ledStateDidChange(isLedOn)
            return .success(())
        default:
            return .failure(CBMATTError(.writeNotPermitted))
        }
    }
    
    public func peripheral(_ peripheral: CBMPeripheralSpec,
                           didReceiveSetNotifyRequest enabled: Bool,
                           for characteristic: CBMCharacteristicMock) -> Result<Void, Error> {
        switch characteristic.uuid {
        case .buttonCharacteristic:
            buttonSubscriptionStateDidChange(enabled)
            return .success(())
        default:
            return .failure(CBMATTError(.requestNotSupported))
        }
    }
    
    public func peripheral(_ peripheral: CBMPeripheralSpec,
                           didDisconnect error: Error?) {
        buttonSubscriptionStateDidChange(false)
    }
    
    func reset() {
        isLedOn = false
        // Note: The button state is not reset, as this depends on the mock
        //       button actually being pressed. Resetting a DK does not make
        //       the button "unpressed" if it was in a pressed state at the time of reset.
        
        print("""
        ----------------------------------------
        *** Booting Mock LBS sample v2.0 ***
        Starting Bluetooth Peripheral LBS sample
        Bluetooth initialized
        Advertising successfully started
        ----------------------------------------
        """)
    }
}

// MARK: - Helper Extensions

private extension Bool {
    
    /// Converts the Boolean value to `Data` using the LBS specification.
    var data: Data {
        return Data([self ? 0x01 : 0x00])
    }
    
}

private extension Data {
    
    /// Converts the `Data` to a Boolean value using the LBS specification.
    var bool: Bool {
        guard self.count == 1 else { return false }
        return self[0] != 0x00
    }
    
}

// MARK: - CoreBluetoothMock

private extension CBMUUID {
    static let ledButtonService: CBMUUID! = CBMUUID(string: "00001523-1212-EFDE-1523-785FEABCD123")
    
    static let buttonCharacteristic: CBMUUID! = CBMUUID(string: "00001524-1212-EFDE-1523-785FEABCD123")
    static let ledCharacteristic: CBMUUID! = CBMUUID(string: "00001525-1212-EFDE-1523-785FEABCD123")
}

private extension CBMServiceMock {
    
    static let blinkyService = CBMServiceMock(
        type: .ledButtonService,
        primary: true,
        characteristics: .buttonCharacteristic, .ledCharacteristic
    )
    
}

private extension CBMCharacteristicMock {
    
    static let buttonCharacteristic = CBMCharacteristicMock(
        type: .buttonCharacteristic,
        properties: [.notify, .read],
        descriptors: CBMClientCharacteristicConfigurationDescriptorMock()
    )

    static let ledCharacteristic = CBMCharacteristicMock(
        type: .ledCharacteristic,
        properties: [.write, .read]
    )
    
}

