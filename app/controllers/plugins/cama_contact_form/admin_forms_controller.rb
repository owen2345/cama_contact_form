class Plugins::CamaContactForm::AdminFormsController < CamaleonCms::Apps::PluginsAdminController
  include Plugins::CamaContactForm::MainHelper
  before_action :set_form, only: ['show','edit','update','destroy']
  add_breadcrumb I18n.t("plugins.cama_contact_form.title", default: 'Contact Form'), :admin_plugins_cama_contact_form_admin_forms_path

  def index
    @forms = current_site.contact_forms.where("parent_id is null").all
    @forms = @forms.paginate(:page => params[:page], :per_page => current_site.admin_per_page)
  end

  def edit
    add_breadcrumb I18n.t("plugins.cama_contact_form.edit_view", default: 'Edit contact form')
    append_asset_libraries({"plugin_contact_form"=> { js: [plugin_asset_path("js/admin_editor.js")], css: [] }})
    render "edit"
  end

  def update
    if @form.update(params.require(:plugins_cama_contact_form_cama_contact_form).permit(:name, :slug))
      settings = {"railscf_mail" => params[:railscf_mail], "railscf_message" => params[:railscf_message], "railscf_form_button" => params[:railscf_form_button]}
      fields = []
      (params[:fields] || {}).each{|k, v|
        v[:field_options][:options] = v[:field_options][:options].values if v[:field_options][:options].present?
        fields << v
      }
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
    @op_fields = values[:fields]
    @forms = current_site.contact_forms.where({parent_id: @form.id})
    @forms = @forms.paginate(:page => params[:page], :per_page => current_site.admin_per_page)
  end

  def manual

  end

  def item_field
    render partial: 'item_field', locals:{ field_type: params[:kind], cid: params[:cid] }
  end

  # here add your custom functions
  private
  def set_form
    begin
      @form = current_site.contact_forms.find_by_id(params[:id])
    rescue
      flash[:error] = "Error form class"
      redirect_to cama_admin_path
    end
  end
end
