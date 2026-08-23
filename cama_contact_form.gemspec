$LOAD_PATH.push File.expand_path('lib', __dir__)

# Maintain your gem's version:
require 'cama_contact_form/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'cama_contact_form'
  s.version     = CamaContactForm::VERSION
  s.authors     = ['Owen Peredo']
  s.email       = ['owenperedo@gmail.com']
  s.homepage    = 'https://github.com/owen2345/cama_contact_form'
  s.summary     = 'Contact Form Plugin for Camaleon CMS'
  s.description = 'Permit to create unlimited of contact forms for Camaleon CMS'
  s.license     = 'MIT'

  s.required_ruby_version = '>= 3.0'

  # No test_files: RubyGems merges it into `files`, which shipped the whole test suite to users.
  s.files = Dir['{app,config,db,lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.md']

  s.add_dependency 'rails'
  s.add_dependency 'recaptcha', '>= 5.0'

  # Test harness: a camaleon_cms-backed dummy Rails app booted under RSpec (see spec/). These are
  # dev-only; the packaged gem (s.files above) ships none of spec/.
  s.add_development_dependency 'factory_bot_rails'
  s.add_development_dependency 'faker'
  s.add_development_dependency 'rspec-rails'
  s.add_development_dependency 'sqlite3'

  # Linting -- same rubocop plugin set as camaleon_cms, so style stays consistent across the two.
  s.add_development_dependency 'rubocop'
  s.add_development_dependency 'rubocop-capybara'
  s.add_development_dependency 'rubocop-factory_bot'
  s.add_development_dependency 'rubocop-performance'
  s.add_development_dependency 'rubocop-rails'
  s.add_development_dependency 'rubocop-rake'
  s.add_development_dependency 'rubocop-rspec'
  s.add_development_dependency 'rubocop-rspec_rails'
end
