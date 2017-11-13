class Plugins::CamaContactForm::FrontController < CamaleonCms::Apps::PluginsFrontController
  include Plugins::CamaContactForm::MainHelper
  include Plugins::CamaContactForm::ContactFormControllerConcern
  
  # here add your custom functions
  def save_form
    flash[:contact_form] = {}
    @form = current_site.contact_forms.find_by_id(params[:id])
    fields = params[:fields]
    errors = []
    success = []

    args = {form: @form, values: fields, flag: true}; hooks_run("contact_form_before_submit", args)
    if args[:flag]
      perform_save_form(@form, fields, success, errors)
      if success.present?
        flash[:contact_form][:notice] = success.join('<br>')
      else
        flash[:contact_form][:error] = errors.join('<br>')
        flash[:values] = fields.delete_if{|k, v| v.class.name == 'ActionDispatch::Http::UploadedFile' }
      end
    end
    if Rails::VERSION::MAJOR >= 5
      params[:format] == 'json' ? render(json: flash.discard(:contact_form).to_hash) : (redirect_back fallback_location: cama_root_path)
    else
      params[:format] == 'json' ? render(json: flash.discard(:contact_form).to_hash) : (redirect_to :back)
    end
  end
end
