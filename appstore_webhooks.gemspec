# frozen_string_literal: true

require_relative "lib/appstore_webhooks/version"

Gem::Specification.new do |spec|
  spec.name = "appstore_webhooks"
  spec.version = AppstoreWebhooks::VERSION
  spec.authors = ["Artem"]
  spec.email = ["artyru@gmail.com"]

  spec.summary = "Rails engine providing persistence and processing for App Store webhooks."
  spec.description = "Adds subscription models, workers, and alerting around the appstore_webhooks payload decoder."
  spec.homepage = "https://github.com/artyru/appstore_webhooks"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) { Dir["{app,config,db,lib}/**/*", "README.md", "Rakefile"] }
  spec.bindir = "bin"
  spec.executables = []
  spec.require_paths = ["lib"]

  spec.add_dependency "aasm"
  spec.add_dependency "appstore_sdk"
  spec.add_dependency "rails", ">= 7.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
