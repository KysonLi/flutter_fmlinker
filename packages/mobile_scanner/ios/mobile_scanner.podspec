#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint mobile_scanner.podspec` to validate before publishing.
#
# iOS integration for Flutter 3.7.x: this fork does not support `sharedDarwinSource`,
# so the darwin sources are vendored under ios/Sources and referenced from here.
Pod::Spec.new do |s|
  s.name             = 'mobile_scanner'
  s.version          = '7.0.1'
  s.summary          = 'An universal scanner for Flutter based on the Vision API.'
  s.description      = <<-DESC
An universal scanner for Flutter based on the Vision API.
                       DESC
  s.homepage         = 'https://github.com/juliansteenbakker/mobile_scanner'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Julian Steenbakker' => 'juliansteenbakker@outlook.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Sources/mobile_scanner/**/*.swift'
  s.ios.dependency 'Flutter'
  s.ios.dependency 'isli_icon_native'
  s.ios.dependency 'isli_line_native'
  s.ios.deployment_target = '12.0'
  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++11',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_OPTIMIZATION_LEVEL' => '3'
  }
  s.swift_version = '5.0'
  s.resource_bundles = {'mobile_scanner_privacy' => ['Sources/mobile_scanner/Resources/PrivacyInfo.xcprivacy']}
end
