# frozen_string_literal: true

source 'https://rubygems.org'

# Declare your gem's dependencies in cama_contact_form.gemspec.
# Bundler will treat runtime dependencies like base dependencies, and
# development dependencies will be added by default to the :development group.
gemspec

# Declare any dependencies that are still in development here instead of in
# your gemspec. These might include edge Rails or gems from your path or
# Git. Remember to move these dependencies to your gemspec before releasing
# your gem to rubygems.org.

# To use a debugger
# gem 'byebug', group: [:development, :test]

gem 'sprockets-rails', '>= 3.5.2'
# Matches the load-time floor in AdminFormsController: camaleon_cms before 2.9.4 lacks the markup detector and
# wipe the submission-throttle counter on every frontend POST.
gem 'camaleon_cms', '>= 2.9.4'

# Development/test dependencies (none are shipped in the packaged gem). A camaleon_cms-backed dummy
# Rails app under spec/ is booted under RSpec.
group :development do
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'rspec-rails'
  gem 'sqlite3'

  # Feature specs (:js) drive the admin UI through a real headless Chrome via Capybara + Selenium.
  # puma is the Capybara rack server; capybara-screenshot saves a screenshot when a :js example fails.
  gem 'capybara'
  gem 'capybara-screenshot'
  gem 'puma'
  gem 'selenium-webdriver'

  # Linting -- same rubocop plugin set as camaleon_cms, so style stays consistent across the two.
  gem 'rubocop'
  gem 'rubocop-capybara'
  gem 'rubocop-factory_bot'
  gem 'rubocop-performance'
  gem 'rubocop-rails'
  gem 'rubocop-rake'
  gem 'rubocop-rspec'
  gem 'rubocop-rspec_rails'
end
