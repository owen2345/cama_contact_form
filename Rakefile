# frozen_string_literal: true

begin
  require 'bundler/setup'
rescue LoadError
  puts 'You must `gem install bundler` and `bundle install` to run rake tasks'
end

require 'rdoc/task'

RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'CamaContactForm'
  rdoc.options << '--line-numbers'
  rdoc.rdoc_files.include('README.md')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

# The plugin's behaviour is exercised host-side in the camaleon_cms repository (see README /
# CHANGELOG); this repo ships no test suite, so the dummy-app engine tasks and the default `test`
# task are intentionally absent. `Bundler::GemHelper.install_tasks` still provides build/install/release.
Bundler::GemHelper.install_tasks
