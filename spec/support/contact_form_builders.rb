# frozen_string_literal: true

# Builders shared by the contact-form request specs, so the settings scaffold a form needs to save
# (`railscf_mail` + `railscf_message` + `railscf_form_button`) lives in exactly one place. They run
# in example scope against the suite-wide shared site (spec/support/shared_site.rb).
module ContactFormBuilders
  def site
    @site ||= CamaleonCms::Site.first.decorate
  end

  # `required` is stored as the string "true" by the form editor (hidden_field_tag + check_box_tag),
  # not as a JSON boolean — the plugin calls `.to_bool`, which Camaleon defines only on String.
  #
  # `settings` merges shallowly: overriding `railscf_mail` replaces the whole hash, so pass it
  # complete.
  def build_form(fields:, settings: {}, name: 'Contact', slug: 'contact')
    site.contact_forms.create!(
      name: name, slug: slug,
      value: { fields: fields }.to_json,
      settings: {
        'railscf_mail' => { 'to' => 'owner@example.com', 'subject' => 'subject', 'body' => 'body' },
        'railscf_message' => {},
        'railscf_form_button' => { 'name_button' => 'Send' }
      }.merge(settings).to_json
    )
  end

  def text_field(cid: 'c1', **overrides)
    { label: 'Name', field_type: 'text', cid: cid, required: 'true', field_options: {} }.merge(overrides)
  end

  # Publishing the fixture post is the harness acting as the site's administrator: camaleon_cms's
  # content_shortcodes gate (camaleon_cms >= 2.9.4) fails closed when no acting user is in scope, and
  # `unfiltered_content!` bypasses only the markup gate, not the shortcode gate. CurrentRequest is an
  # ActiveSupport::CurrentAttributes, so `.set` scopes the acting user/site to the block and restores
  # whatever an example had already arranged.
  def publish_form_on_sample_post(slug: 'contact')
    admin = CamaManager.get_user_class_name.constantize.find_by!(username: 'admin')
    CurrentRequest.set(user: admin, site: site) do
      site.the_post('sample-post').update!(content: "[forms slug='#{slug}']")
    end
  end

  # The bare submission POST. Whether it succeeds or fails validation is the example's business;
  # the redisplay-oriented specs follow the redirect themselves.
  def submit_contact_form(form, fields)
    post '/plugins/cama_contact_form/save_form', params: { id: form.id, fields: fields }
  end
end

RSpec.configure do |config|
  config.include ContactFormBuilders, type: :request
  # The throttle feature spec drives the same builders through a real browser.
  config.include ContactFormBuilders, type: :feature
end
