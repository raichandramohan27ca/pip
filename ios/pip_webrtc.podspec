#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pip.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'pip_webrtc'
  s.version          = '0.0.1'
  s.summary          = 'A PiP plugin tuned for WebRTC iOS video calls.'
  s.description      = <<-DESC
A fork of pip plugin for Picture in Picture, using the video call PiP approach compatible with .playAndRecord audio session.
                       DESC
  s.homepage         = 'https://github.com/raichandramohan27ca/pip'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Sylar' => 'peilinok@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'WebRTC-SDK'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flutter_pip_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
