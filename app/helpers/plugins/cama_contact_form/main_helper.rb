module Plugins::CamaContactForm::MainHelper
  include Recaptcha::Adapters::ViewMethods
  def self.included(klass)
    klass.helper_method [:cama_form_element_bootstrap_object, :cama_form_shortcode, :cf_h] rescue "" # here your methods accessible from views
  end

  def contact_form_on_export(args)
    args[:obj][:plugins][self_plugin_key] = JSON.parse(current_site.contact_forms.to_json(:include => [:responses]))
  end

  def contact_form_on_import(args)
    plugins = args[:data][:plugins]
    if plugins[self_plugin_key.to_sym].present?
      plugins[self_plugin_key.to_sym].each do |contact|
        unless current_site.contact_forms.where(slug: contact[:slug]).first.present?
          sba_data = ActionController::Parameters.new(contact)
          contact_new = current_site.contact_forms.new(sba_data.permit(:name, :slug, :count, :description, :value, :settings))
          if contact_new.save!
            if contact[:get_field_groups] # save group fields
              save_field_group(contact_new, contact[:get_field_groups])
            end
            save_field_values(contact_new, contact[:field_values])

            if contact[:responses].present? # saving responses for this contact
              contact[:responses].each do |response|
                sba_data = ActionController::Parameters.new(response)
                contact_new.responses.create!(sba_data.permit(:name, :slug, :count, :description, :value, :settings))
              end
            end
            args[:messages] << "Saved Plugin Contact Form: #{contact_new.name}"
          end
        end
      end
    end
  end

  # here all actions on plugin destroying
  # plugin: plugin model
  def contact_form_on_destroy(plugin)

  end

  # here all actions on going to active
  # you can run sql commands like this:
  # results = ActiveRecord::Base.connection.execute(query);
  # plugin: plugin model
  def contact_form_on_active(plugin)

  end

  # here all actions on going to inactive
  # plugin: plugin model
  def contact_form_on_inactive(plugin)

  end

  def contact_form_admin_before_load
    admin_menu_append_menu_item("settings", {icon: "envelope-o", title: t('plugins.cama_contact_form.title', default: 'Contact Form'), url: admin_plugins_cama_contact_form_admin_forms_path, datas: "data-intro='This plugin permit you to create you contact forms with desired fields and paste your short_code in any content.' data-position='right'"})
  end

  def contact_form_app_before_load
    shortcode_add('forms', plugin_view("forms_shorcode"), "This is a shortocode for contact form to permit you to put your contact form in any content. Sample: [forms slug='key-for-my-form']")
  end

  def contact_form_front_before_load

  end

  # ============== HTML ==================
  # This returns the format of the plugin shortcode.
  def cama_form_shortcode(slug)
    "[forms slug=#{slug}]"
  end

  # Escape a value for interpolation into an HTML *attribute value*.
  #
  # CGI.escapeHTML rather than ERB::Util.html_escape: the latter is a no-op on an html_safe string,
  # which would let such a value close its own attribute.
  #
  # Which positions get this, and which render as markup, is decided by HTML context rather than by
  # trust -- because the two contexts are protected by different mechanisms:
  #
  #   Attribute values (class="...", value="...", name="...") are ALWAYS escaped. Sanitizing cannot
  #   protect this context: `form-control" onfocus="alert(1)` contains no tags, so an HTML sanitizer
  #   passes it through untouched and rendering it raw injects a live event handler. There is no
  #   markup use case for a CSS class or a prefilled input value, so nothing is lost by escaping.
  #
  #   Element content (labels, descriptions, option text, button text, the form wrappers and the
  #   field template) renders as markup, and is sanitized when the form is SAVED unless the author
  #   holds :manage, :contact_form_unfiltered_html. That is what lets a trusted author put <strong>
  #   or a link in a field label and have guests see it rendered.
  #
  # One value crosses both contexts: a visitor's own submission (values[cid]). It is always escaped,
  # in every position, with no permission able to exempt it -- unauthenticated input never passes
  # through the save-time sanitizer.
  def cf_h(value)
    CGI.escapeHTML(value.to_s)
  end

  # Substitute a placeholder without letting the replacement text be reinterpreted. String#sub/#gsub
  # treat backslash sequences in a String replacement as backreferences, so a value containing "\1"
  # or "\\" would be mangled; the block form passes the replacement through untouched.
  def cf_sub(subject, placeholder, replacement)
    subject.sub(placeholder) { replacement }
  end

  def cf_gsub(subject, placeholder, replacement)
    subject.gsub(placeholder) { replacement }
  end

  # form contact with css bootstrap
  def cama_form_element_bootstrap_object(form, object, values)
    html = ""
    object.each do |ob|
      ob[:label] = ob[:label].to_s.translate
      ob[:description] = ob[:description].to_s.translate
      r = {field: ob, form: form, template: (ob[:field_options][:template].present? ? ob[:field_options][:template] :  Plugins::CamaContactForm::CamaContactForm::field_template), custom_class: (ob[:field_options][:field_class] rescue nil), custom_attrs: {id: ob[:cid] }.merge((JSON.parse(ob[:field_options][:field_attributes]) rescue {})) }
      hooks_run("contact_form_item_render", r)
      ob = r[:field]
      ob[:custom_class] = r[:custom_class]
      ob[:custom_attrs] = r[:custom_attrs]
      ob[:custom_attrs][:required] = 'true' if ob[:required].present? && ob[:required].to_bool
      field_options = ob[:field_options]
      for_name = ob[:label].to_s
      f_name = "fields[#{ob[:cid]}]"
      cid = ob[:cid].to_sym

      temp2 = ""

      # Every interpolation below is a data position and is escaped. `custom_attrs.to_attr_format` is
      # escaped by Camaleon's Hash extension, and the field template itself stays raw by contract.
      current_value = cf_h(values[cid] || ob[:default_value].to_s.translate)
      esc_f_name = cf_h(f_name)
      esc_type = cf_h(ob[:field_type])

      case ob[:field_type].to_s
        when 'paragraph','textarea'
          temp2 = "<textarea #{ob[:custom_attrs].to_attr_format} name=\"#{esc_f_name}\" maxlength=\"#{cf_h(field_options[:maxlength] || 500)}\"  class=\"#{cf_h(ob[:custom_class].presence || 'form-control')}  \">#{current_value}</textarea>"
        when 'radio'
          temp2=  cama_form_select_multiple_bootstrap(ob, ob[:label], ob[:field_type],values)
        when 'checkboxes'
          temp2=  cama_form_select_multiple_bootstrap(ob, ob[:label], "checkbox",values)
        when 'submit'
          temp2 = "<button #{ob[:custom_attrs].to_attr_format} type=\"#{esc_type}\" name=\"#{esc_f_name}\"  class=\"#{cf_h(ob[:custom_class].presence || 'btn btn-default')}\">#{ob[:label]}</button>"
        when 'button'
          temp2 = "<button #{ob[:custom_attrs].to_attr_format} type='button' name=\"#{esc_f_name}\" class=\"#{cf_h(ob[:custom_class].presence || 'btn btn-default')}\">#{ob[:label]}</button>"
        when 'reset_button'
          temp2 = "<button #{ob[:custom_attrs].to_attr_format} type='reset' name=\"#{esc_f_name}\" class=\"#{cf_h(ob[:custom_class].presence || 'btn btn-default')}\">#{ob[:label]}</button>"
        when 'text', 'website', 'email'
          class_type = ""
          class_type = "railscf-field-#{ob[:field_type]}" if ob[:field_type]=="website"
          class_type = "railscf-field-#{ob[:field_type]}" if ob[:field_type]=="email"
          temp2 = "<input #{ob[:custom_attrs].to_attr_format} type=\"#{esc_type}\" value=\"#{current_value}\" name=\"#{esc_f_name}\"  class=\"#{cf_h(ob[:custom_class].presence || 'form-control')} #{cf_h(class_type)}\">"
        when 'captcha'
          if form.recaptcha_enabled?
            temp2 = recaptcha_tags
          else
            temp2 = cama_captcha_tag(5, {}, {class: "#{ob[:custom_class].presence || 'form-control'} field-captcha required"}.merge(ob[:custom_attrs]))
          end
        when 'file'
          temp2 = "<input multiple=\"multiple\" type=\"file\" value=\"\" name=\"#{esc_f_name}[]\" #{ob[:custom_attrs].to_attr_format} class=\"#{cf_h(ob[:custom_class].presence || 'form-control')}\">"
        when 'dropdown'
          temp2 = cama_form_select_multiple_bootstrap(ob, ob[:label], "select",values)
        else
      end
      r[:template] = cf_sub(r[:template], '[ci]', temp2)
      r[:template] = cf_sub(r[:template], '[descr ci]', field_options[:description].to_s.translate).sub('<p></p>', '')
      html += cf_gsub(r[:template], '[label ci]', for_name)
    end
    html
  end

  def cama_form_select_multiple_bootstrap(ob, title, type, values)
    options = ob[:field_options][:options]
    include_other_option = ob[:field_options][:include_other_option]
    other_input = ""

    f_name = "fields[#{ob[:cid]}]"
    cid = ob[:cid].to_sym
    html = ""

    esc_type = cf_h(type)
    esc_cid = cf_h(ob[:cid])
    esc_f_name = cf_h(f_name)
    esc_class = cf_h(ob[:custom_class])

    if type == "radio" || type == "checkbox"
      other_input = (include_other_option)? "<div class=\"#{esc_type} #{esc_class}\"> <label for=\"#{esc_cid}\"><input id=\"#{esc_cid}-other\" type=\"#{esc_type}\" name=\"#{cf_h("#{title.downcase}[]")}\" class=\"\">Other <input type=\"text\" /></label></div>" : " "
    else
      html = "<select #{ob[:custom_attrs].to_attr_format} name=\"#{esc_f_name}\" class=\"#{esc_class}\">"
    end

    options.each do |op|
      label = op[:label].translate
      # The option value is the label lowercased with spaces collapsed to underscores; escape the
      # result, not the source, so the value attribute matches what is compared against `values[cid]`.
      option_value = label.downcase.gsub(" ", "_")
      if type == "radio" || type == "checkbox"
        html += "<div class=\"#{esc_type} #{esc_class}\">
                    <label for=\"#{esc_cid}\">
                      <input #{ob[:custom_attrs].to_attr_format} type=\"#{esc_type}\" #{'checked' if op[:checked].to_s.cama_true?} name=\"#{esc_f_name}[]\" class=\"\" value=\"#{cf_h(option_value)}\">
                      #{label}
                    </label>
                  </div>"
      else
        html += "<option  value=\"#{cf_h(option_value)}\" #{"selected" if option_value == values[cid] || op[:checked].to_s.cama_true? } >#{label}</option>"
      end
    end

    if type == "radio" || type == "checkbox"
      html += other_input
    else
      html += " </select>"
    end
  end
end
