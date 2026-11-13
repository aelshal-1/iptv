Pod::Spec.new do |s|
  s.name             = 'native_pip'
  s.version          = '0.0.1'
  s.summary          = 'AVPlayer view with Picture in Picture.'
  s.description      = 'AVPlayer platform view with system Picture in Picture for the IPTV player.'
  s.homepage         = 'https://github.com/aelshal-1/iptv'
  s.license          = { :type => 'MIT' }
  s.author           = { 'aelshal' => 'aelshal' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.frameworks       = 'AVFoundation', 'AVKit'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
