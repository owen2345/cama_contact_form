# frozen_string_literal: true

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
end
