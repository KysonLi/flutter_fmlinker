#
# ISLI line (1D) decoder pod.
# Separate framework module so mobile_scanner's Swift code can `import isli_line_native`.
# Kept as its own target because isli/ and linecode/ share identical cpp basenames,
# which Xcode's build system drops within a single target.
#
Pod::Spec.new do |s|
  s.name             = 'isli_line_native'
  s.version          = '1.0.0'
  s.summary          = 'ISLI line C++ decoder exposed through an Objective-C++ wrapper.'
  s.description      = <<-DESC
Objective-C++ wrapper around the vendored ISLI line C++ decoder, used by mobile_scanner.
                       DESC
  s.homepage         = 'https://github.com/isli/mobile_scanner'
  s.license          = { :type => 'MIT' }
  s.author           = { 'isli' => 'dev@isli.local' }
  s.source           = { :path => '.' }
  s.source_files = 'ISLILineDecoderWrapper.{h,mm}', 'linecode/**/*.{cpp,h,hpp}'
  s.public_header_files = 'ISLILineDecoderWrapper.h'
  s.ios.deployment_target = '12.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++11',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_OPTIMIZATION_LEVEL' => '3'
  }
end
