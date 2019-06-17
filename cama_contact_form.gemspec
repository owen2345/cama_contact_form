$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "cama_contact_form/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "cama_contact_form"
  s.version     = CamaContactForm::VERSION
  s.authors     = ["Owen Peredo"]
  s.email       = ["owenperedo@gmail.com"]
  s.homepage    = ""
  s.summary     = "Contact Form Plugin for Camaleon CMS"
  s.description = "Permit to create unlimited of contact forms for Camaleon CMS"
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "rails"
  s.add_dependency "recaptcha", ">= 5.0"
  s.add_development_dependency "sqlite3"
end
