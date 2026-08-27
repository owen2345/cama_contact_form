# frozen_string_literal: true

require 'cama_contact_form/version'

module CamaContactForm
  # camaleon_cms version gate. The plugin needs a core new enough to (a) expose
  # `CamaleonCms::UnsafeMarkup` (the admin markup gate delegates to it) and (b) not wipe `Rails.cache`
  # on every frontend POST -- camaleon_cms before 2.9.4 did, through the bundled front_cache plugin,
  # which left the submission throttle counter erased each submission and unable to ever trigger.
  #
  # The floor is not expressible as a gemspec dependency (camaleon_cms depends on this gem, so a
  # reverse pin would be circular), and older camaleon_cms releases pin `cama_contact_form` wide
  # enough to resolve this release. So the plugin verifies the version itself, at boot, from the
  # engine initializer -- a seat every process passes through before serving, unlike a controller
  # class body, which under lazy loading may never load before FrontController#save_form is served.
  # It fails fast with an actionable error rather than a broken gate or a silently dead throttle at
  # the first untrusted request.
  module CoreCompatibility
    MINIMUM_CORE_VERSION = '2.9.4'

    module_function

    def compatible_core?
      defined?(CamaleonCms::VERSION) &&
        Gem::Version.new(CamaleonCms::VERSION) >= Gem::Version.new(MINIMUM_CORE_VERSION)
    end

    def ensure_compatible_core!
      return if compatible_core?

      raise "cama_contact_form #{CamaContactForm::VERSION} requires camaleon_cms >= #{MINIMUM_CORE_VERSION}."
    end
  end
end
