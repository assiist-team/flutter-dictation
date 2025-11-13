Pod::Spec.new do |s|
  s.name             = 'flutter_dictation'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for native iOS dictation'
  s.description      = <<-DESC
A Flutter plugin providing native iOS dictation with low-latency speech recognition.
                       DESC
  s.homepage         = 'https://github.com/yourusername/flutter_dictation'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Name' => 'your.email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  
  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'SWIFT_OBJC_BRIDGING_HEADER' => '${PODS_TARGET_SRCROOT}/Classes/FlutterDictation-Bridging-Header.h'
  }
end

