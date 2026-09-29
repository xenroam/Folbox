platform :osx, '14.0'

target 'Folbox' do
  use_frameworks!

  pod 'Sparkle', '~> 2.9.4'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_MODULE_VERIFIER'] = 'NO'
    end
  end
end
