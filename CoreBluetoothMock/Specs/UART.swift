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

// MARK: - UART

public class UART {
    
    // MARK: Private
    
    private var isNotificationEnabled: Bool
    private var messageCounter: Int
    
    // MARK: Properties
    
    public let name: String
    
    // MARK: init
    
    public init(name: String = "Nordic_UART") {
        self.isNotificationEnabled = false
        self.messageCounter = 0
        self.name = name
    }
    
    // MARK: spec
    
    public private(set) lazy var spec = CBMPeripheralSpec
        .simulatePeripheral(proximity: .far)
        .advertising(
            advertisementData: [
                CBMAdvertisementDataIsConnectable : true as NSNumber,
                CBMAdvertisementDataLocalNameKey : name,
                CBMAdvertisementDataServiceUUIDsKey : [CBMUUID.uart]
            ],
            withInterval: 2.0,
            delay: 5.0,
            alsoWhenConnected: false
        )
        .connectable(
            name: name,
            services: [.uart],
            delegate: self,
            connectionInterval: 0.02,
        )
        .build()
}

// MARK: - UARTCBMPeripheralSpecDelegate

extension UART: CBMPeripheralSpecDelegate {
    
    public func peripheral(_ peripheral: CBMPeripheralSpec,
                    didReceiveWriteRequestFor characteristic: CBMCharacteristicMock,
                    data: Data) -> Result<Void, Error> {
        switch characteristic.uuid {
        case CBMUUID.uartRx:
            if (isNotificationEnabled) {
                let receivedMessage = String(data: data, encoding: .utf8)
                messageCounter += 1
                let reply = "Received message #\(messageCounter):\n\(receivedMessage ?? "<empty>")"
                let replyData = reply.data(using: .utf8) ?? Data()
                peripheral.simulateValueUpdate(replyData, for: CBMCharacteristicMock.uartTx)
                return .success(())
            }
            return .failure(CBMATTError(.requestNotSupported))
        default:
            return .failure(CBMATTError(.writeNotPermitted))
        }
    }
    
    public func peripheral(_ peripheral: CBMPeripheralSpec, didReceiveSetNotifyRequest enabled: Bool, for characteristic: CBMCharacteristicMock) -> Result<Void, Error> {
        switch characteristic.uuid {
        case .uartTx:
            isNotificationEnabled = enabled
        default:
            return .failure(CBMATTError(.requestNotSupported))
        }
        
        return .success(())
    }
    
    public func peripheral(_ peripheral: CBMPeripheralSpec, didReceiveReadRequestFor characteristic: CBMCharacteristicMock) -> Result<Data, any Error> {
        return .failure(CBMATTError(.readNotPermitted))
    }
}

// MARK: - CoreBluetoothMock

private extension CBMUUID {
    static let uart: CBMUUID! = CBMUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let uartRx: CBMUUID! = CBMUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let uartTx: CBMUUID! = CBMUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    
    static let cccd = CBMUUID(string: "2902")
}

private extension CBMDescriptorMock {
    static let cccd = CBMDescriptorMock(type: .cccd)
}

private extension CBMCharacteristicMock {
    
    static let uartTx = CBMCharacteristicMock(
        type: .uartTx, properties: .notify, descriptors: .cccd
    )
    
    static let uartRx = CBMCharacteristicMock(
        type: .uartRx, properties: [.write],
    )
}

private extension CBMServiceMock {
    
    static let uart = CBMServiceMock(
        type: .uart, primary: true,
        characteristics: .uartRx, .uartTx,
    )
}
