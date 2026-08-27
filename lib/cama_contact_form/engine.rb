# frozen_string_literal: true

require 'cama_contact_form/core_compatibility'

# Top-level namespace for the cama_contact_form gem.
module CamaContactForm
  # Rails engine that registers the plugin (and its `forms` shortcode) with a Camaleon CMS host.
  class Engine < ::Rails::Engine
    # Fail fast at boot on a camaleon_cms too old for the markup gate or the submission throttle to
    # work (see CoreCompatibility). Seated here, not in a controller class body, so the check runs in
    # every process -- including a lazy-loaded one that would otherwise serve save_form before the
    # admin controller (which carries the other half of the requirement) ever loads.
    initializer 'cama_contact_form.ensure_compatible_core' do
      CamaContactForm::CoreCompatibility.ensure_compatible_core!
    end

    # Declare this plugin's shortcode name to Camaleon's boot-time shortcode registry so the CMS
    # save-time `content_shortcodes` gate can detect and gate it. Detection needs the name at boot
    # because the per-request shortcode list is empty at an admin save; the render-time handler stays
    # verbatim in main_helper (`shortcode_add`) -- authorship is gated, output is not filtered.
    # Guarded so the plugin still loads against camaleon_cms versions predating the registry.
    initializer 'cama_contact_form.register_shortcodes' do
      CamaleonCms::ShortcodeRegistry.register('forms') if defined?(CamaleonCms::ShortcodeRegistry)
    end
  end
end
