Pod::Spec.new do |s|
  s.name             = 'CoreBluetoothMock'
  s.version          = '1.0.6'
  s.summary          = 'Mocking library for CoreBluetooth.'

  s.description      = <<-DESC
This is a mocking library for CoreBluetooth framework. Allows to mock a Bluetooth Low Energy
device and test the app on simulator.
                       DESC

  s.homepage         = 'https://github.com/nordicsemi/IOS-CoreBluetooth-Mock'
  s.license          = { :type => 'BSD 3-Clause', :file => 'LICENSE' }
  s.author           = { 'Aleksander Nowakowski' => 'aleksander.nowakowski@nordicsemi.no' }
  s.source           = { :git => 'https://github.com/nordicsemi/IOS-CoreBluetooth-Mock.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/nordictweets'
  s.swift_versions   = ['4.2', '5.0', '5.1', '5.2', '5.3', '5.4', '5.5', '5.6', '5.7', '5.8', '5.9']

  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'
  s.tvos.deployment_target = '12.0'
  s.watchos.deployment_target = '4.0'

  s.source_files = 'CoreBluetoothMock/**/*'
  s.resource_bundles = {
    'PrivacyInfo' => ['PrivacyInfo.xcprivacy']
  }
end
