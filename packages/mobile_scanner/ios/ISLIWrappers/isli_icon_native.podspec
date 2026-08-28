#
# ISLI icon (2D shield) decoder pod.
# Separate framework module so mobile_scanner's Swift code can `import isli_icon_native`.
# Kept as its own target because isli/ and linecode/ share identical cpp basenames,
# which Xcode's build system drops within a single target.
#
Pod::Spec.new do |s|
  s.name             = 'isli_icon_native'
  s.version          = '1.0.0'
  s.summary          = 'ISLI icon C++ decoder exposed through an Objective-C++ wrapper.'
  s.description      = <<-DESC
Objective-C++ wrapper around the vendored ISLI icon C++ decoder, used by mobile_scanner.
                       DESC
  s.homepage         = 'https://github.com/isli/mobile_scanner'
  s.license          = { :type => 'MIT' }
  s.author           = { 'isli' => 'dev@isli.local' }
  s.source           = { :path => '.' }
  s.source_files = 'ISLIDecoderWrapper.{h,mm}', 'isli/**/*.{cpp,h,hpp}'
  s.public_header_files = 'ISLIDecoderWrapper.h'
  s.ios.deployment_target = '12.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++11',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_OPTIMIZATION_LEVEL' => '3'
  }
end
