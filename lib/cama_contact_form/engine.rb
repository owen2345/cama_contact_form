# frozen_string_literal: true

# Top-level namespace for the cama_contact_form gem.
module CamaContactForm
  # Rails engine that registers the plugin (and its `forms` shortcode) with a Camaleon CMS host.
  class Engine < ::Rails::Engine
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
