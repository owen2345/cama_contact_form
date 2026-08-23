# frozen_string_literal: true

# Adapted from camaleon_cms's spec/factories/site.rb. The two includes expose the CMS helper methods
# (site_after_install, hook_run, current_site, ...) on the object evaluating the callbacks below.
# The upstream slug sequence keyed off a running Capybara server is dropped -- this harness has no
# browser, so a plain unique slug is all multi-site resolution needs here.
include CamaleonCms::SiteHelper
include CamaleonCms::HooksHelper

FactoryBot.define do
  factory :site, class: 'CamaleonCms::Site' do
    name { Faker::Name.unique.name }
    sequence(:slug) { |n| "test-site-#{n}" }
    description { Faker::Lorem.sentence }

    transient do
      theme { 'default' }
      skip_intro { true }
    end

    after(:create) do |site, evaluator|
      # site_after_install resolves current_site; pin the new site as current for the install.
      previous_site = CurrentRequest.site
      CurrentRequest.site = site.decorate
      site_after_install(site, evaluator.theme)
      site.set_option('save_intro', true) if evaluator.skip_intro
      # Production mints a random admin password and forces a change on first login. Reset the admin
      # to the well-known credentials a spec can sign in with, and clear the must-change marker.
      admin = site.users.where(role: 'admin').first
      if admin
        admin.update(password: 'admin123', password_confirmation: 'admin123')
        admin.delete_meta('must_change_password')
      end
    ensure
      CurrentRequest.site = previous_site
    end
  end
end
