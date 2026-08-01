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
        # Redisplaying the submission is the only reason it ever reaches the page, so a submission
        # containing anything malign is refused whole and echoed back not at all. Filtering it down
        # to the safe fields would be more work for a worse result: the visitor gets a half-filled
        # form, and every future edit to the rendering has to stay in step with the filter.
        #
        # Stamped with the form it was judged against. The gate walks `@form.fields` for the form
        # named by params[:id], but the redisplay page hands flash[:values] to *every* shortcode on
        # it, and auto-generated cids are `c1, c2, …` in every form -- so a value cleared as textarea
        # content for one form was being rendered into a value attribute by another.
        #
        # `@form` is whatever `find_by_id` returned, which is nil for a deleted or bogus id -- a
        # POST anyone can make without credentials. `unsafe_submitted?` fails closed on that, so the
        # guard below is belt and braces for the `@form.id` read on the line after it.
        if @form.present? && fields.respond_to?(:delete_if) && !unsafe_submitted?(@form, fields)
          flash[:values] = fields.delete_if{|k, v| v.class.name == 'ActionDispatch::Http::UploadedFile' }
          flash[:values_form_id] = @form.id
        end
      end
    end
    if Rails::VERSION::MAJOR >= 5
      params[:format] == 'json' ? render(json: flash.discard(:contact_form).to_hash) : (redirect_back fallback_location: cama_root_path)
    else
      params[:format] == 'json' ? render(json: flash.discard(:contact_form).to_hash) : (redirect_to :back)
    end
  end
end
