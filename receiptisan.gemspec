# frozen_string_literal: true

require_relative 'lib/receiptisan/version'

Gem::Specification.new do | spec |
  spec.name          = 'receiptisan'
  spec.version       = Receiptisan::VERSION
  spec.authors       = ['yokenzan']
  spec.email         = ['31175068+yokenzan@users.noreply.github.com']

  spec.summary       = 'Library to parse receipt UKE contents'
  spec.description   = spec.summary
  spec.homepage      = 'https://github.com/yokenzan/receiptisan'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.3.0')

  spec.metadata['homepage_uri']    = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri']   = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { | f | f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { | f | File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency 'dry-cli'
  spec.add_dependency 'month'
  spec.add_dependency 'nkf'
  spec.add_dependency 'logger'

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata['rubygems_mfa_required'] = 'true'
end
