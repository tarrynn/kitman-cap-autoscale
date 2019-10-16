# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "kitman-cap-autoscale"
  spec.version       = "1.1.1"
  spec.authors       = ["wal", "catalin"]
  spec.email         = ["wal@kitmanlabs.com", "catalin.gheonea@gmail.com"]
  spec.summary       = "Capistrano tasks for utilizing AWS Auto Scaling"
  spec.description   = "Capistrano tasks for utilizing AWS Auto Scaling"
  spec.homepage      = "https://github.com/KitmanLabs/kitman-cap-autoscale"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency 'bundler', '~> 1.11'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.7'
  spec.add_development_dependency 'dotenv', '~> 2.0'

  spec.add_runtime_dependency 'capistrano', '>= 3.0.0'
  spec.add_runtime_dependency 'aws-sdk-ec2', '~> 1'
  spec.add_runtime_dependency 'aws-sdk-autoscaling', '~> 1'
end
