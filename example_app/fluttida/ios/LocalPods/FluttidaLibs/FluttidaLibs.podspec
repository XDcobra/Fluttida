Pod::Spec.new do |s|
  s.name         = 'FluttidaLibs'
  s.version      = '0.1.0'
  s.summary      = 'Vendored libcurl and OpenSSL for Fluttida'
  s.homepage     = 'https://example.com/FluttidaLibs'
  s.license      = { :type => 'MIT' }
  s.author       = { 'Fluttida' => 'noreply@example.com' }
  s.platform     = :ios, '12.0'
  s.source       = { :path => '.' }

  # Vendored xcframeworks (paths are relative to this podspec directory)
  s.vendored_frameworks = '../Runner/Frameworks/libcurl.xcframework', '../Runner/Frameworks/OpenSSL.xcframework'

  # Public headers (pull from the frameworks' Headers directories)
  s.public_header_files = '../Runner/Frameworks/**/Headers/**/*.h'

  # Do not require subspecs; this is a small local vendor pod
end
