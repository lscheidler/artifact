# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'artifact/version'

Gem::Specification.new do |spec|
  spec.name          = "artifact"
  spec.version       = Artifact::VERSION
  spec.authors       = ["Lars Eric Scheidler"]
  spec.email         = ["lscheidler@liventy.de"]

  spec.summary       = %q{artifact deployment tool.}
  spec.description   = %q{tool to publish and deploy artifacts. Uses S3 as storage backend.}
  spec.homepage      = "https://github.com/lscheidler/artifact"
  spec.license       = "Apache-2.0"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "memory_profiler", "~> 0.9"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "yard", "~> 0.9.7"
  spec.add_runtime_dependency "aws-sdk-s3", "~> 1"
  spec.add_runtime_dependency "gpgme", "~> 2.0.5"
  spec.add_runtime_dependency "rubyzip", "~>1.2.1"
end
