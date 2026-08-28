# frozen_string_literal: true

# A contact form and, through `parent_id`, its stored response rows, scoped to a site.
class Plugins::CamaContactForm::CamaContactForm < ActiveRecord::Base
  include Plugins::CamaContactForm::MainHelper

  self.table_name = 'plugins_contact_forms'
  belongs_to :site, class_name: 'CamaleonCms::Site'
  # attr_accessible :site_id, :name, :description, :count, :slug, :value, :settings, :parent_id

  # A self-referential parent/child: a form and its stored response rows. There is no reciprocal
  # `belongs_to :parent` to point `inverse_of` at, so the cop is disabled for this association only.
  # rubocop:disable-next Rails/InverseOf
  has_many :responses, class_name: 'Plugins::CamaContactForm::CamaContactForm', foreign_key: :parent_id,
                       dependent: :destroy

  validates :name, presence: true
  validates :slug, uniqueness: { scope: :site_id }

  before_validation :before_validating
  before_create :fix_save_settings
  before_destroy :delete_uploaded_files

  default_scope { order(created_at: :desc) }

  # Example of the stored `value` JSON, kept on one line for copy-paste:
  # rubocop:disable Layout/LineLength
  # [{"label":"Untitled","field_type":"text","required":true,"field_options":{"size":"large","field_class":"Default"},"cid":"c2"},{"label":"Untitled","field_type":"paragraph","required":true,"field_options":{"size":"large","field_class":"Default"},"cid":"c6"},{"label":"Untitled","field_type":"captcha","required":true,"field_options":{"field_class":"Default"},"cid":"c10"},{"label":"Untitled","field_type":"checkboxes","required":true,"field_options":{"options":[{"label":"Default","checked":false},{"label":"Default","checked":false}],"field_class":"Default","description":"description\n"},"cid":"c12"}]
  # rubocop:enable Layout/LineLength
  def fields
    @_the_fields ||= JSON.parse(value || '{"fields": []}').with_indifferent_access
    Array(@_the_fields[:fields])
  end

  def the_settings
    @the_settings ||= JSON.parse(settings || '{}').with_indifferent_access
  end

  # The three settings containers, always readable. A form that has never been saved carries
  # `settings` of `{}`, and a partial update can leave any of them unset -- so every caller in the
  # admin views guards its read with `rescue ''`, while the ones that do not (the public shortcode,
  # the mailer) raised NoMethodError on every request until someone edited the database by hand.
  def mail_settings
    settings_hash(:railscf_mail)
  end

  def form_button_settings
    settings_hash(:railscf_form_button)
  end

  def message_settings
    settings_hash(:railscf_message)
  end

  def the_message(key, default)
    r = message_settings[key].to_s.translate
    r.presence || default
  end

  def self.field_template
    "<div class='form-group'>\n\t <label>[label ci]</label>\n\t<p>[descr ci]</p>\n\t<div>[ci]</div> \n</div>"
  end

  # define recaptcha settings
  def set_captcha_settings!
    return unless recaptcha_enabled?

    Recaptcha.configure do |config|
      config.site_key = the_settings[:recaptcha_site_key]
      config.secret_key = the_settings[:recaptcha_secret_key]
    end
  end

  # verify if recaptcha was enabled for this form
  # this method can be overwritten if recaptcha was already defined on initializers to return true as default
  def recaptcha_enabled?
    the_settings[:recaptcha_site_key].present?
  end

  private

  def settings_hash(key)
    value = the_settings[key]
    value.is_a?(Hash) ? value : {}.with_indifferent_access
  end

  def before_validating
    slug = self.slug
    slug = name if slug.blank?
    self.slug = slug.to_s.parameterize
  end

  def fix_save_settings
    self.value = { 'fields' => [] }.to_json if value.blank?
    self.settings = {}.to_json if settings.blank?
  end

  # Deletes the files this response uploaded, on destroy. Those files live directly in the site's
  # `public/contact_form/<site_id>` directory, and this is confined to delete only from there: each
  # stored path is reduced to its basename and rebuilt inside that root, so a path that is absolute,
  # climbs out with `../`, or is otherwise hostile -- as an untrusted import can leave in a
  # response's settings -- can at most name a file already sitting in the root, never one outside
  # it. Missing parent, non-hash settings and non-string entries are tolerated rather than raising
  # on a destroy any `:manage, :plugins` holder can trigger.
  def delete_uploaded_files
    return if parent_id.nil?

    form = self.class.find_by(id: parent_id)
    response_data = the_settings[:fields]
    return if form.nil? || !response_data.is_a?(Hash)

    media_root = Rails.public_path.join('contact_form', site_id.to_s).to_s
    form.fields
        .select { |f| f[:field_type] == 'file' }
        .flat_map { |f| response_data[f[:cid].to_sym] }
        .compact
        .each do |file|
          target = File.expand_path(File.basename(file.to_s), media_root)
          FileUtils.rm_f(target) if File.dirname(target) == media_root
        end
  end
end
