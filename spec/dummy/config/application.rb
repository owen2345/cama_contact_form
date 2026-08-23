require File.expand_path('boot', __dir__)

require 'rails'
# Pick the frameworks you want:
require 'active_model/railtie'
# require "active_job/railtie"
require 'active_record/railtie'
# require "active_storage/engine"
require 'action_controller/railtie'
require 'action_mailer/railtie'
# require "action_mailbox/engine"
# require "action_text/engine"
require 'action_view/railtie'
# require "action_cable/engine"
require 'sprockets/railtie'
require 'rails/test_unit/railtie'
Bundler.require(*Rails.groups)
require 'camaleon_cms'
# The plugin under test. Loading its engine registers it as a gem-mode Camaleon plugin (via
# config/camaleon_plugin.json) and puts its app/, config/initializers and db/migrate on the paths.
require 'cama_contact_form'

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails.version.to_f
    config.autoloader = :zeitwerk
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    config.active_record.legacy_connection_handling = false if Rails.version.to_f >= 6.1 && Rails.version.to_f < 7.1
  end
end
