Pod::Spec.new do |spec|

  spec.name         = "ICloudManager"
  spec.version      = "0.0.1"
  spec.summary      = "iCloud manager"
  spec.description  = <<-DESC
                        Test cocoapods for iCloud manager
                        DESC
  spec.homepage     = "https://github.com/supermanyqq/ICloudManager"
  spec.license      = { :type => "MIT", :file => "LICENSE" }

  spec.author       = { "kmqq" => "supermanyqq@163.com" }
  spec.platform     = :ios, "12.0"

  spec.source       = { :git => "https://github.com/supermanyqq/ICloudManager.git", :tag => "#{spec.version}" }

  spec.source_files  = "ICloudManager", "ICloudManager/**/*.{h,m}"
  spec.exclude_files = "ICloudManager/Exclude"

  spec.swift_version = "5.0"
  spec.ios.deployment_target = "12.0"

end
