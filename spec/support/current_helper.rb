# frozen_string_literal: true

# Helper methods to set ActiveSupport::CurrentAttributes (CurrentRequest) values in specs.
# Adapted from camaleon_cms's spec/support/current_helper.rb.
module CurrentSpecHelper
  # Set current user for the duration of the example (or until reset).
  def store_current_user(user)
    CurrentRequest.user = user
  end

  # Set current site for the duration of the example (or until reset).
  def store_current_site(site)
    CurrentRequest.site = site
  end

  # Convenience: set both user and site.
  def set_current(user: nil, site: nil)
    store_current_user(user) if user
    store_current_site(site) if site
  end

  # Reset Current to avoid leakage between examples.
  def reset_current
    CurrentRequest.reset
  end
end
