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
# Floor: the plugin's security model requires a core newer than 2.9.2 (the upload content scanner and
# the save-time gate), so tests must never resolve to the vulnerable 2.9.2 (audit CF-8). The lockfile
# is gitignored for a gem, so this floor is where the requirement is documented and enforced.
gem 'camaleon_cms', '>= 2.9.3'
