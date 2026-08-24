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

  def publish_form_on_sample_post(slug: 'contact')
    site.the_post('sample-post').update!(content: "[forms slug='#{slug}']")
  end

  # The bare submission POST. Whether it succeeds or fails validation is the example's business;
  # the redisplay-oriented specs follow the redirect themselves.
  def submit_contact_form(form, fields)
    post '/plugins/cama_contact_form/save_form', params: { id: form.id, fields: fields }
  end
end

RSpec.configure do |config|
  config.include ContactFormBuilders, type: :request
end
