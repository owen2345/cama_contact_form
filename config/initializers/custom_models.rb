Rails.application.config.to_prepare do
  CamaleonCms::Site.class_eval do
    has_many :contact_forms, :class_name => "Plugins::CamaContactForm::CamaContactForm", foreign_key: :site_id, dependent: :destroy
  end
end