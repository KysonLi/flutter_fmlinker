#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint umeng_common_sdk.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'umeng_common_sdk'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin.'
  s.description      = <<-DESC
A new Flutter plugin.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '8.0'
  s.dependency 'UMCommon'
  s.dependency 'UMDevice'
  # UMCommon 引用了 StoreKit 的 SKAdNetworkCoarseConversionValueLow，
  # 未链接 StoreKit 时 App 链接阶段会报 Undefined symbol。
  # 写进 podspec 后 CocoaPods 会把 -framework StoreKit 写进 Pods-Runner 的 xcconfig。
  s.frameworks = 'StoreKit'
  # 该常量是 weak import，但 iOS 16 及更早的 SDK 未导出，
  # 用 -U 允许其保持未定义（运行时按动态查找），兼容 Xcode 14/15/16 构建。
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-Wl,-U,_SKAdNetworkCoarseConversionValueLow'
  }
  s.static_framework = true

  # Flutter.framework does not contain a i386 slice. Only x86_64 simulators are supported.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
end
