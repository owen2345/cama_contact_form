class Plugins::CamaContactForm::AdminFormsController < CamaleonCms::Apps::PluginsAdminController
  include Plugins::CamaContactForm::MainHelper
  include Plugins::CamaContactForm::ContactFormControllerConcern
  before_action :set_form, only: ['show','edit','update','destroy']
  add_breadcrumb I18n.t("plugins.cama_contact_form.title", default: 'Contact Form'), :admin_plugins_cama_contact_form_admin_forms_path

  def index
    @forms = current_site.contact_forms.where("parent_id is null").all
    @forms = @forms.paginate(:page => params[:page], :per_page => current_site.admin_per_page)
  end

  def show

  end

  def edit
    add_breadcrumb I18n.t("plugins.cama_contact_form.edit_view", default: 'Edit contact form')
    render "edit"
  end

  def update
    if @form.update(params.require(:plugins_cama_contact_form_cama_contact_form).permit(:name, :slug))
      settings = {"railscf_mail" => params[:railscf_mail], "railscf_message" => params[:railscf_message], "railscf_form_button" => params[:railscf_form_button], recaptcha_site_key: params[:recaptcha_site_key], recaptcha_secret_key: params[:recaptcha_secret_key]}
      fields = []
      (params[:fields] || {}).each{|k, v|
        v[:field_options][:options] = v[:field_options][:options].values if v[:field_options][:options].present?
        fields << v
      }
      settings, fields = sanitize_unfiltered_html(settings, fields) unless trusted_for_unfiltered_html?
      @form.update({settings: settings.to_json, value: {fields: fields}.to_json})
      flash[:notice] = t('.updated_success', default: 'Updated successfully')
      redirect_to action: :edit, id: @form.id
    else
      edit
    end
  end

  def create
    @form = current_site.contact_forms.new(params.require(:plugins_cama_contact_form_cama_contact_form).permit(:name, :slug))
    if @form.save
      flash[:notice] = "#{t('.created', default: 'Created successfully')}"
      redirect_to action: :edit, id: @form.id
    else
      flash[:error] = @form.errors.full_messages.join(', ')
      redirect_to action: :index
    end
  end

  def destroy
    flash[:notice] = "#{t('.deleted', default: 'Destroyed successfully')}" if @form.destroy
    redirect_to action: :index
  end

  def responses
    add_breadcrumb I18n.t("plugins.cama_contact_form.list_responses", default: 'Contact form records')
    @form = current_site.contact_forms.where({id: params[:admin_form_id]}).first
    values = JSON.parse(@form.value).to_sym
    @op_fields = values[:fields].select{ |field| relevant_field? field }
    @forms = current_site.contact_forms.where({parent_id: @form.id})
    @forms = @forms.paginate(:page => params[:page], :per_page => current_site.admin_per_page)
  end

  def del_response
    response = current_site.contact_forms.find_by_id(params[:response_id])
    if response.present? && response.destroy
      flash[:notice] = "#{t('.actions.msg_deleted', default: 'The response has been deleted')}"
    end
    redirect_to action: :responses
  end

  def manual

  end

  def item_field
    render partial: 'item_field', locals:{ field_type: params[:kind], cid: params[:cid] }
  end

  # here add your custom functions
  private

  # Two stored settings are rendered unescaped by design -- the markup wrapping a form
  # (railscf_mail#previous_html / #after_html) -- as is each field's template. Escaping them would
  # break the feature, so they are sanitized on save instead, unless the saving user is trusted.
  #
  # field_options#field_attributes is deliberately NOT in this set. It is JSON, not HTML (running an
  # HTML sanitizer over it would corrupt it), and it is already safe at render time: Camaleon's
  # Hash#to_attr_format escapes attribute values and drops keys that are not valid attribute names.
  UNFILTERED_HTML_SETTINGS = %w[previous_html after_html].freeze

  # Mirrors CamaleonCms::Post#trusted_for_unfiltered_html?: read the acting user and site from
  # CurrentRequest and fail closed (sanitize) when either is missing, so saves from background jobs,
  # rake tasks or the console are sanitized regardless of role. The site is guarded as well because
  # Ability#initialize dereferences it for non-admin users and would otherwise raise mid-save.
  def trusted_for_unfiltered_html?
    user = CurrentRequest.user
    site = CurrentRequest.site
    return false if user.blank? || site.blank?

    CamaleonCms::Ability.new(user, site).can?(:manage, :contact_form_unfiltered_html)
  end

  def sanitize_unfiltered_html(settings, fields)
    mail = settings["railscf_mail"]
    if mail.present?
      UNFILTERED_HTML_SETTINGS.each do |key|
        mail[key] = CamaleonRecord.cama_sanitize_translatable(mail[key].to_s) if mail[key].present?
      end
    end

    fields.each do |field|
      options = field[:field_options]
      next if options.blank? || options[:template].blank?

      options[:template] = CamaleonRecord.cama_sanitize_translatable(options[:template].to_s)
    end

    [settings, fields]
  end

  def set_form
    begin
      @form = current_site.contact_forms.find_by_id(params[:id])
    rescue
      flash[:error] = "Error form class"
      redirect_to cama_admin_path
    end
  end
end
