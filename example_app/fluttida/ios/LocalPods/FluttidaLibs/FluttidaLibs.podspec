Pod::Spec.new do |s|
  s.name         = 'FluttidaLibs'
  s.version      = '0.1.0'
  s.summary      = 'Vendored libcurl for Fluttida'
  s.homepage     = 'https://example.com/FluttidaLibs'
  s.license      = { :type => 'MIT' }
  s.author       = { 'Fluttida' => 'noreply@example.com' }
  s.platform     = :ios, '13.0'
  s.source       = { :path => '.' }

  # Vendored xcframeworks (paths are relative to this podspec directory)
  # Paths should point to the app's Runner/Frameworks directory (two levels up from
  # this podspec: LocalPods/FluttidaLibs -> LocalPods -> ios)
  s.vendored_frameworks = '../../Runner/Frameworks/libcurl.xcframework'

  # Public headers (pull from the frameworks' Headers directories)
  s.public_header_files = '../../Runner/Frameworks/**/Headers/**/*.h'

  # Do not require subspecs; this is a small local vendor pod
end
