Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # The test environment is used exclusively to run your application's
  # test suite. You never need to work with it otherwise.
  config.cache_classes = true

  # Eager load code on boot so a single spec exercises the whole app (mirrors camaleon_cms's dummy;
  # also surfaces zeitwerk/plugin load errors up front).
  config.eager_load = true

  # :debug logs every SQL statement to log/test.log, which measurably slows the suite and grows the
  # file unboundedly.
  config.log_level = :warn

  # Configure static file server for tests with Cache-Control for performance.
  config.public_file_server.enabled = true
  config.static_cache_control = 'public, max-age=3600'

  # Show full error reports and disable caching.
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false

  config.assets.check_precompiled_asset = false

  # Raise exceptions instead of rendering exception templates.
  config.action_dispatch.show_exceptions = if ::Rails::VERSION::STRING < '7.2.0'
                                             false
                                           else
                                             :none
                                           end

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Tell Action Mailer not to deliver emails to the real world. The :test delivery method accumulates
  # sent emails in the ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Randomize the order test cases are executed.
  config.active_support.test_order = :random

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr
end
