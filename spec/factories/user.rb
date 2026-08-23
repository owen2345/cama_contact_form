# frozen_string_literal: true

# Adapted from camaleon_cms's spec/factories/user.rb.
FactoryBot.define do
  factory :user, class: CamaManager.get_user_class_name do
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    email { Faker::Internet.unique.email }
    username { Faker::Internet.unique.username }
    password { '12345678' }
    password_confirmation { '12345678' }
    site { CamaleonCms::Site.first || create(:site) }

    factory :user_admin do
      role { 'admin' }
    end
  end
end
