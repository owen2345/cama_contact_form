# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

require 'spec_helper'
require File.expand_path('dummy/config/environment', __dir__)
# The factories use Faker for unique names. It's a dev-group gem, so Bundler.require (which loads only
# :default + :test in this env) doesn't pull it in -- require it explicitly.
require 'faker'

# Refuse to run against a non-test environment: an exported RAILS_ENV must never point the suite's
# schema load / transactional fixtures at a development or production database.
abort("The Rails environment must be 'test' (is '#{Rails.env}')") unless Rails.env.test?

# `maintain_test_schema!` checks for pending migrations against `Migrator.migrations_paths`. Camaleon
# assembles the real, multi-engine migration set at boot (auto_include_migrations), but the schema is
# checked in as spec/dummy/db/schema.rb and loaded wholesale. Point the pending-check at the dummy's
# own (empty) migrate dir so a fresh checkout -- schema file present, DB not yet migrated -- still
# loads and verifies cleanly rather than tripping on gem-supplied migrations it can't see.
ActiveRecord::Migrator.migrations_paths = [File.expand_path('dummy/db/migrate', __dir__)]

require 'rspec/rails'

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# camaleon_cms is loaded here as a released gem, not from this repo, so its engine points factory_bot
# at its own gem-dir spec/factories (not shipped in the packaged gem). Point factory_bot at this
# plugin's factories and reload so :site and :user resolve.
FactoryBot.definition_file_paths = [File.expand_path('factories', __dir__)]
FactoryBot.reload

# Support helpers (CurrentSpecHelper, etc.).
Dir[File.expand_path('support/**/*.rb', __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.include CurrentSpecHelper
  config.include FactoryBot::Syntax::Methods

  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!

  config.before do
    # Clear per-request Current state so nothing leaks between examples.
    CurrentRequest.reset
    # These caches are memoized at boot and during installs; a site created in one example must not
    # leak into the next through them.
    CamaleonCms::Site.instance_variable_set(:@main_site, nil)
    PluginRoutes.instance_variable_set(:@all_sites, nil)
    PluginRoutes.instance_variable_get(:@cache)&.clear
    # Core's brute-force counters live in Rails.cache (FileStore here) and outlive the per-example
    # transaction, so clear them or a run of frontend submissions in one example bans the shared
    # client IP for the next.
    Rails.cache.delete_matched(/cama_captcha_attack|plugins_attack_ban/) if Rails.cache.respond_to?(:delete_matched)
    # A between-example reset, not a scoped translation, so I18n.with_locale (a block) does not fit.
    I18n.locale = I18n.default_locale # rubocop:disable Rails/I18nLocaleAssignment
  end
end
