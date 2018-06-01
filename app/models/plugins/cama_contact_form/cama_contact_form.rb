class Plugins::CamaContactForm::CamaContactForm < ActiveRecord::Base
  include Plugins::CamaContactForm::MainHelper
  self.table_name = 'plugins_contact_forms'
  belongs_to :site, class_name: "CamaleonCms::Site"
  # attr_accessible :site_id, :name, :description, :count, :slug, :value, :settings, :parent_id

  has_many :responses, :class_name => "Plugins::CamaContactForm::CamaContactForm", :foreign_key => :parent_id, dependent: :destroy
  validates :name, presence: true
  validates_uniqueness_of :slug, scope: :site_id

  before_validation :before_validating
  before_create :fix_save_settings
  before_destroy :delete_uploaded_files

  default_scope { order(created_at: :desc) }

  # [{"label":"Untitled","field_type":"text","required":true,"field_options":{"size":"large","field_class":"Default"},"cid":"c2"},{"label":"Untitled","field_type":"paragraph","required":true,"field_options":{"size":"large","field_class":"Default"},"cid":"c6"},{"label":"Untitled","field_type":"captcha","required":true,"field_options":{"field_class":"Default"},"cid":"c10"},{"label":"Untitled","field_type":"checkboxes","required":true,"field_options":{"options":[{"label":"Default","checked":false},{"label":"Default","checked":false}],"field_class":"Default","description":"description\n"},"cid":"c12"}]
  def fields
    @_the_fields ||= JSON.parse(self.value || '{fields: []}').with_indifferent_access
    @_the_fields[:fields]
  end

  def the_settings
    @_the_settings ||= JSON.parse(self.settings || '{}').with_indifferent_access
  end

  def the_message(key, default)
    r = self.the_settings[:railscf_message][key].to_s.translate
    r.present? ? r : default
  end

  def self.field_template
    "<div class='form-group'>\n\t <label>[label ci]</label>\n\t<p>[descr ci]</p>\n\t<div>[ci]</div> \n</div>"
  end
  
  # define recaptcha settings
  def set_captcha_settings!
    if recaptcha_enabled?
      Recaptcha.configure do |config|
        config.site_key  = the_settings[:recaptcha_site_key]
        config.secret_key = the_settings[:recaptcha_secret_key]
      end
    end
  end
  
  # verify if recaptcha was enabled for this form
  # this method can be overwritten if recaptcha was already defined on initializers to return true as default 
  def recaptcha_enabled?
    the_settings[:recaptcha_site_key].present?
  end

  private
  def before_validating
    slug = self.slug
    slug = self.name if slug.blank?
    self.slug = slug.to_s.parameterize
  end

  def fix_save_settings
    self.value = {"fields" => []}.to_json unless self.value.present?
    self.settings = {}.to_json unless self.settings.present?
  end

  def delete_uploaded_files
    return if self.parent_id.nil?
    form = self.class.find_by_id self.parent_id
    response_data = the_settings[:fields]
    file_cids = form.fields
                    .select { |f| f[:field_type] == 'file' }
                    .map { |f| f[:cid].to_sym }

    file_cids
        .flat_map { |cid| response_data[cid] }
        .map { |file| file.sub Rails.application.routes.url_helpers.cama_root_url, Rails.public_path.to_s }
        .each { |file| File.delete file if File.exists? file }
  end
end