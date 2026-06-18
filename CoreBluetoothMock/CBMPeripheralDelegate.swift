/*
* Copyright (c) 2020, Nordic Semiconductor
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

import CoreBluetooth

/// A protocol that provides updates on the use of a peripheral’s services.
///
/// The delegate of a CBPeripheral object must adopt the ``CBMPeripheralDelegate`` protocol. The delegate
/// uses this protocol’s methods to monitor the discovery, exploration, and interaction of a remote peripheral’s services
/// and properties. This protocol doesn’t have any required methods.
public protocol CBMPeripheralDelegate: AnyObject {
    
    /// This method is invoked when the name of peripheral changes.
    /// - Parameter peripheral: The peripheral providing this update.
    func peripheralDidUpdateName(_ peripheral: CBMPeripheral)
    
    /// This method is invoked when the `services` of peripheral have been changed.
    /// At this point, the designated ``CBMService`` objects have been invalidated.
    /// Services can be re-discovered via ``CBMPeripheral/discoverServices(_:)``.
    /// - Parameters:
    ///   - peripheral: The peripheral providing this update.
    ///   - invalidatedServices: The services that have been invalidated.
    @available(iOS 7.0, *)
    func peripheral(_ peripheral: CBMPeripheral,
                    didModifyServices invalidatedServices: [CBMService])
    
    /// This method returns the result of a ``CBMPeripheral/readRSSI()`` call.
    /// - Parameters:
    ///   - peripheral: The peripheral providing this update.
    ///   - RSSI: The current RSSI of the link.
    ///   - error: If an error occurred, the cause of the failure.
    func peripheral(_ peripheral: CBMPeripheral,
                    didReadRSSI RSSI: NSNumber, error: Error?)
    
    /// This method returns the result of a ``CBMPeripheral/discoverServices(_:)`` call.
    /// If the service(s) were read successfully, they can be retrieved via peripheral's services property.
    /// - Parameters:
    ///   - peripheral: The peripheral providing this information.
    ///   - error: If an error occurred, the cause of the failure.
    func peripheral(_ peripheral: CBMPeripheral,
                    didDiscoverServices error: Error?)
    
    /// This method returns the result of a ``CBMPeripheral/discoverIncludedServices(_:for:)`` call.
    /// If the included service(s) were read successfully, they can be retrieved via service's
    /// ``CBMService/includedServices`` property.
    /// - Parameters:
    ///   - peripheral: The peripheral providing this information.
    ///   - service: The ``CBMService`` object containing the included services.
    ///   - error: If an error occurred, the cause of the failure.
    func peripheral(_ peripheral: CBMPeripheral,
                    didDiscoverIncludedServicesFor service: CBMService,
                    error: Error?)
    
    /// This method returns the result of a ``CBMPeripheral/discoverCharacteristics(_:for:)`` call.
    /// If the characteristic(s) were read successfully, they can be retrieved via service's
    /// ``CBMService/characteristics`` property.
    /// - Parameters:
    ///   - peripheral: The peripheral providing this information.
    ///   - service: The ``CBMService`` object containing the characteristic(s).
    ///   - error: If an error occurred, the cause of the failure.
    func peripheral(_ peripheral: CBMPeripheral,
                    didDiscoverCharacteristicsFor service: CBMService,
                    error: Error?)
    
    /// This method returns the result of a ``CBMPeripheral/discoverDescriptors(for:)`` call.
    /// If the descriptors were read successfully, they can be retrieved via characteristic's
    /// `descriptors` property.
    /// - Parameters:
    ///   - peripheral: The peripheral providing this information.
    ///   - characteristic: A ``CBMCharacteristic`` object.
    ///   - error: If an error occurred, the cause of the failure.
    func peripheral(_ peripheral: CBMPeripheral,
                    didDiscoverDescriptorsFor characteristic: CBMCharacteristic,
                    error: Error?)
    
    /// This method returns the result of a ``CBMPeripheral/setNotifyValue(_:for:)`` call.
    /// - Parameters:
    ///   - peripheral: The peripheral providing this information.
    ///   - characteristic: A ``CBMCharacteristic`` object.
    ///   - error: If an error occurred, the cause of the failure.
    func peripheral(_ peripheral: CBMPeripheral,
                    didUpdateNotificationStateFor characteristic: CBMCharacteristic,
                    error: Error?)
    
    /// This method is invoked after a ``CBMPeripheral/readValue(for:)-1hqxp`` call, or upon
    /// receipt of a notification/indication.
    /// - Parameters:
    ///   - peripheral: The peripheral providing this information.
    ///   - characteristic: A ``CBMCharacteristic`` object.
    ///   - error: If an error occurred, the cause of the failure.
    func peripheral(_ peripheral: CBMPeripheral,
                    didUpdateValueFor characteristic: CBMCharacteristic,
                    error: Error?)
    
    /// This method returns the result of a ``CBMPeripheral/readValue(for:)-3xyb1`` call.
    /// - Parameters:
    ///   - peripheral: The peripheral providing this information.
    ///   - descriptor: A ``CBMDescriptor`` object.
    ///   - error: If an error occurred, the cause of the failure.
    func peripheral(_ peripheral: CBMPeripheral,
                    didUpdateValueFor descriptor: CBMDescriptor, error: Error?)
    
    /// This method returns the result of a ``CBMPeripheral/writeValue(_:for:type:)`` call,
    /// when the `.withResponse` type is used.
    ///
    /// - Important: On iOS 10 this callback was also incorrectly called for
    ///             `.withoutResponse` type.
    /// - Parameters:
    ///   - peripheral: The peripheral providing this information.
    ///   - characteristic: A ``CBMCharacteristic`` object.
    ///   - error: If an error occurred, the cause of the failure.
    func peripheral(_ peripheral: CBMPeripheral,
                    didWriteValueFor characteristic: CBMCharacteristic,
                    error: Error?)
    
    /// This method returns the result of a ``CBMPeripheral/writeValue(_:for:)`` call.
    /// - Parameters:
    ///   - peripheral: The peripheral providing this information.
    ///   - descriptor: A ``CBMDescriptor`` object.
    ///   - error: If an error occurred, the cause of the failure.
    func peripheral(_ peripheral: CBMPeripheral,
                    didWriteValueFor descriptor: CBMDescriptor, error: Error?)
    
    /// This method is invoked after a failed call to ``CBMPeripheral/writeValue(_:for:type:)``, when
    /// peripheral is again ready to send characteristic value updates.
    /// - Parameter peripheral: The peripheral providing this update.
    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBMPeripheral)

    /// This method returns the result of a ``CBMPeripheral/openL2CAPChannel(_:)`` call.
    /// - Parameters:
    ///   - peripheral: The peripheral providing this information.
    ///   - channel: A ``CBML2CAPChannel`` object.
    ///   - error: If an error occurred, the cause of the failure.
    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    func peripheral(_ peripheral: CBMPeripheral,
                    didOpen channel: CBML2CAPChannel?, error: Error?)
    
    /// This method returns the results of a channel sounding procedure.
    /// - Parameters:
    ///     - peripheral: The peripheral providing this information.
    ///     - results: A ``CBMChannelSoundingProcedureResults`` object.
    @available(iOS 27.0, *)
    func peripheral(_ peripheral: CBMPeripheral,
                    didReceive results: CBMChannelSoundingProcedureResults?, error: Error?)
    
    /// This method returns when channel sounding completes.
    /// - Parameters:
    ///     - peripheral The peripheral providing this information.
    ///     - error: If an error occurred, the cause of the failure.
    @available(iOS 27.0, *)
    func peripheral(_ peripheral: CBMPeripheral, didCompleteChannelSoundingSession error: Error?)
}

public extension CBMPeripheralDelegate {
    
    func peripheralDidUpdateName(_ peripheral: CBMPeripheral) {
        // optional method
    }

    func peripheral(_ peripheral: CBMPeripheral,
                    didModifyServices invalidatedServices: [CBMService]) {
        // optional method
    }
    
    func peripheral(_ peripheral: CBMPeripheral,
                    didReadRSSI RSSI: NSNumber, error: Error?) {
        // optional method
    }

    func peripheral(_ peripheral: CBMPeripheral,
                    didDiscoverServices error: Error?) {
        // optional method
    }

    func peripheral(_ peripheral: CBMPeripheral,
                    didDiscoverIncludedServicesFor service: CBMService, error: Error?) {
        // optional method
    }

    func peripheral(_ peripheral: CBMPeripheral,
                    didDiscoverCharacteristicsFor service: CBMService, error: Error?) {
        // optional method
    }

    func peripheral(_ peripheral: CBMPeripheral,
                    didUpdateValueFor characteristic: CBMCharacteristic, error: Error?) {
        // optional method
    }

    func peripheral(_ peripheral: CBMPeripheral,
                    didWriteValueFor characteristic: CBMCharacteristic, error: Error?) {
        // optional method
    }

    func peripheral(_ peripheral: CBMPeripheral,
                    didUpdateNotificationStateFor characteristic: CBMCharacteristic, error: Error?) {
        // optional method
    }
    
    func peripheral(_ peripheral: CBMPeripheral,
                    didDiscoverDescriptorsFor characteristic: CBMCharacteristic, error: Error?) {
        // optional method
    }
    
    func peripheral(_ peripheral: CBMPeripheral,
                    didUpdateValueFor descriptor: CBMDescriptor, error: Error?) {
        // optional method
    }
    
    func peripheral(_ peripheral: CBMPeripheral,
                    didWriteValueFor descriptor: CBMDescriptor, error: Error?) {
        // optional method
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBMPeripheral) {
        // optional method
    }

    @available(iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    func peripheral(_ peripheral: CBMPeripheral,
                    didOpen channel: CBML2CAPChannel?, error: Error?) {
        // optional method
    }
    
    @available(iOS 27.0, *)
    func peripheral(_ peripheral: CBMPeripheral,
                    didReceive results: CBMChannelSoundingProcedureResults?, error: Error?) {
        // optional method
    }
    
    @available(iOS 27.0, *)
    func peripheral(_ peripheral: CBMPeripheral, didCompleteChannelSoundingSession error: Error?) {
        // optional method
    }
}
