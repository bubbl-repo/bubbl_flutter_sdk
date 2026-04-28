Pod::Spec.new do |s|
  s.name             = 'bubbl_flutter_sdk'
  s.version          = '2.4.0'
  s.summary          = 'Flutter wrapper for Bubbl native iOS and Android SDKs.'
  s.description      = <<-DESC
Flutter plugin that wraps Bubbl native SDK APIs for bootstrapping, geofence updates,
notifications, surveys, and analytics.
                       DESC
  s.homepage         = 'https://bubbl.tech'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Bubbl' => 'support@bubbl.tech' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  s.dependency 'Flutter'
  s.dependency 'BubblSDK', '2.4.0'
  s.dependency 'FirebaseCore'
  s.dependency 'Firebase/Messaging'

  s.platform = :ios, '15.1'
  s.swift_version = '5.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
