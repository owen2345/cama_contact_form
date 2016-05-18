class Plugins::CamaContactForm::CamaContactForm < ActiveRecord::Base
  self.table_name = 'plugins_contact_forms'
  belongs_to :site, class_name: "CamleonCms::Site"
  # attr_accessible :site_id, :name, :description, :count, :slug, :value, :settings, :parent_id

  has_many :responses, :class_name => "Plugins::CamaContactForm::CamaContactForm", :foreign_key => :parent_id, dependent: :destroy
  validates :name, presence: true
  validates_uniqueness_of :slug, scope: :site_id

  before_validation :before_validating
  before_create :fix_save_settings

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
end