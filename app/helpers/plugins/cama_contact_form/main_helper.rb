# frozen_string_literal: true

module Plugins::CamaContactForm::MainHelper
  include Recaptcha::Adapters::ViewMethods
  def self.included(klass)
    klass.helper_method %i[cama_form_element_bootstrap_object cama_form_shortcode]
  rescue StandardError
    ''
    # here your methods accessible from views
  end

  def contact_form_on_export(args)
    args[:obj][:plugins][self_plugin_key] = JSON.parse(current_site.contact_forms.to_json(include: [:responses]))
  end

  def contact_form_on_import(args)
    plugins = args[:data][:plugins]
    return if plugins[self_plugin_key.to_sym].blank?

    plugins[self_plugin_key.to_sym].each do |contact|
      next if current_site.contact_forms.where(slug: contact[:slug]).first.present?

      sba_data = ActionController::Parameters.new(contact)
      contact_new = current_site.contact_forms.new(sba_data.permit(:name, :slug, :count, :description, :value,
                                                                   :settings))
      next unless contact_new.save!

      save_field_group(contact_new, contact[:get_field_groups]) if contact[:get_field_groups] # save group fields
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

  # here all actions on plugin destroying
  # plugin: plugin model
  def contact_form_on_destroy(plugin); end

  # here all actions on going to active
  # you can run sql commands like this:
  # results = ActiveRecord::Base.connection.execute(query);
  # plugin: plugin model
  def contact_form_on_active(plugin); end

  # here all actions on going to inactive
  # plugin: plugin model
  def contact_form_on_inactive(plugin); end

  def contact_form_admin_before_load
    admin_menu_append_menu_item(
      'settings',
      { icon: 'envelope-o',
        title: t('plugins.cama_contact_form.title', default: 'Contact Form'),
        url: admin_plugins_cama_contact_form_admin_forms_path,
        datas: "data-intro='This plugin permit you to create you contact forms with desired fields " \
               "and paste your short_code in any content.' data-position='right'" }
    )
  end

  def contact_form_app_before_load
    shortcode_add('forms', plugin_view('forms_shorcode'),
                  'This is a shortocode for contact form to permit you to put your contact form in any ' \
                  "content. Sample: [forms slug='key-for-my-form']")
  end

  def contact_form_front_before_load; end

  # ============== HTML ==================
  # This returns the format of the plugin shortcode.
  def cama_form_shortcode(slug)
    "[forms slug=#{slug}]"
  end

  # Nothing in this file escapes anything, by design. Every value it interpolates -- an author's
  # labels, descriptions, classes, default values, wrappers and templates, a visitor's redisplayed
  # submission, and the structural identifiers the form builder generates -- reaches the page
  # VERBATIM.
  #
  # That is safe because it is enforced at the gate rather than at the sink. The admin controller
  # refuses to store content an untrusted author may not write, and refuses structurally malformed
  # values from anyone; the front controller refuses a submission carrying anything malign and
  # echoes it back not at all. Stored content therefore always equals written content, so rendering
  # it verbatim introduces nothing the writer did not put there -- and an author holding
  # :manage, :contact_form_unfiltered_html can put markup, or script, anywhere in a form and have
  # guests receive it exactly as written.
  #
  # Emit a field's custom attributes verbatim.
  #
  # Camaleon's Hash#to_attr_format is deliberately NOT used here. That method escapes values and
  # drops keys that are not valid attribute names, which is exactly right for its other callers --
  # plugins and themes handing it data from who-knows-where -- but wrong for this one.
  # field_attributes is authored content: it is validated when the form is saved, and an author
  # holding the unfiltered-HTML grant is entitled to emit an event handler through it.
  def cf_attrs(attrs)
    (attrs || {}).map { |key, value| "#{key} = \"#{value}\"" }.join(' ')
  end

  # Substitute every placeholder in ONE pass, so no replacement is ever scanned for the next
  # placeholder. Substituting in sequence meant `[label ci]` was searched for in the field markup
  # `[ci]` had just produced -- so a visitor typing the literal `[label ci]` into a message had the
  # author's label spliced into the middle of the textarea that was echoing it back.
  #
  # `[ci]` and `[descr ci]` keep first-occurrence semantics and `[label ci]` all-occurrence, which is
  # what the three separate sub/sub/gsub calls did.
  #
  # The block form of #gsub is used throughout: a String replacement would treat `\1` or `\\` in the
  # value as a backreference and silently mangle it.
  CF_PLACEHOLDER = /\[(?:ci|label ci|descr ci)\]/
  CF_REPEATABLE_PLACEHOLDERS = ['[label ci]'].freeze

  def cf_substitute(template, replacements)
    seen = Hash.new(0)
    template.to_s.gsub(CF_PLACEHOLDER) do |placeholder|
      seen[placeholder] += 1
      if seen[placeholder] == 1 || CF_REPEATABLE_PLACEHOLDERS.include?(placeholder)
        replacements.fetch(placeholder, placeholder)
      else
        placeholder
      end
    end
  end

  # form contact with css bootstrap
  def cama_form_element_bootstrap_object(form, object, values)
    html = ''
    object.each do |ob|
      ob[:label] = ob[:label].to_s.translate
      ob[:description] = ob[:description].to_s.translate
      template = ob[:field_options][:template].presence ||
                 Plugins::CamaContactForm::CamaContactForm.field_template
      r = { field: ob, form: form, template: template, custom_class: begin
        ob[:field_options][:field_class]
      rescue StandardError
        nil
      end, custom_attrs: { id: ob[:cid] }.merge(begin
        JSON.parse(ob[:field_options][:field_attributes])
      rescue StandardError
        {}
      end) }
      hooks_run('contact_form_item_render', r)
      ob = r[:field]
      ob[:custom_class] = r[:custom_class]
      ob[:custom_attrs] = r[:custom_attrs]
      # `cama_true?`, not `to_bool`: `to_bool` raises ArgumentError on anything outside its two
      # patterns, so a stored `required` of `maybe` was a 500 on every visit to the page.
      ob[:custom_attrs][:required] = 'true' if ob[:required].to_s.cama_true?
      field_options = ob[:field_options]
      for_name = ob[:label].to_s
      f_name = "fields[#{ob[:cid]}]"
      cid = ob[:cid].to_sym

      temp2 = ''

      # Both a redisplayed submission and the author's default_value render verbatim: each was
      # validated before it could be stored or stashed, so neither can carry anything the submitter
      # was not permitted to write.
      current_value = values[cid] || ob[:default_value].to_s.translate

      case ob[:field_type].to_s
      when 'paragraph', 'textarea'
        temp2 = "<textarea #{cf_attrs(ob[:custom_attrs])} name=\"#{f_name}\" " \
                "maxlength=\"#{field_options[:maxlength] || 500}\"  " \
                "class=\"#{ob[:custom_class].presence || 'form-control'}  \">#{current_value}</textarea>"
      when 'radio'
        temp2 = cama_form_select_multiple_bootstrap(ob, ob[:label], ob[:field_type], values)
      when 'checkboxes'
        temp2 = cama_form_select_multiple_bootstrap(ob, ob[:label], 'checkbox', values)
      when 'submit'
        temp2 = "<button #{cf_attrs(ob[:custom_attrs])} type=\"#{ob[:field_type]}\" name=\"#{f_name}\"  " \
                "class=\"#{ob[:custom_class].presence || 'btn btn-default'}\">#{ob[:label]}</button>"
      when 'button'
        temp2 = "<button #{cf_attrs(ob[:custom_attrs])} type='button' name=\"#{f_name}\" " \
                "class=\"#{ob[:custom_class].presence || 'btn btn-default'}\">#{ob[:label]}</button>"
      when 'reset_button'
        temp2 = "<button #{cf_attrs(ob[:custom_attrs])} type='reset' name=\"#{f_name}\" " \
                "class=\"#{ob[:custom_class].presence || 'btn btn-default'}\">#{ob[:label]}</button>"
      when 'text', 'website', 'email'
        class_type = ''
        class_type = "railscf-field-#{ob[:field_type]}" if ob[:field_type] == 'website'
        class_type = "railscf-field-#{ob[:field_type]}" if ob[:field_type] == 'email'
        temp2 = "<input #{cf_attrs(ob[:custom_attrs])} type=\"#{ob[:field_type]}\" value=\"#{current_value}\" " \
                "name=\"#{f_name}\"  class=\"#{ob[:custom_class].presence || 'form-control'} #{class_type}\">"
      when 'captcha'
        if form.recaptcha_enabled?
          temp2 = recaptcha_tags
        else
          # The one field type whose attributes do not go through cf_attrs: cama_captcha_tag builds
          # its markup with Rails' `tag`, which escapes values and rewrites malformed names. That is
          # a documented exception to this file's verbatim contract rather than a gap in it -- `tag`
          # is the stricter of the two, so a trusted author's quoted value is escaped here and a
          # malformed attribute name is mangled rather than emitted. Left as it is deliberately:
          # reproducing cf_attrs would mean rebuilding the helper's output by string surgery, which
          # is a real risk of breaking the captcha for a consistency gain and no security gain.
          captcha_class = "#{ob[:custom_class].presence || 'form-control'} field-captcha required"
          temp2 = cama_captcha_tag(5, {}, { class: captcha_class }.merge(ob[:custom_attrs]))
        end
      when 'file'
        temp2 = "<input multiple=\"multiple\" type=\"file\" value=\"\" name=\"#{f_name}[]\" " \
                "#{cf_attrs(ob[:custom_attrs])} class=\"#{ob[:custom_class].presence || 'form-control'}\">"
      when 'dropdown'
        temp2 = cama_form_select_multiple_bootstrap(ob, ob[:label], 'select', values)
      end
      r[:template] = cf_substitute(r[:template],
                                   '[ci]' => temp2,
                                   '[descr ci]' => field_options[:description].to_s.translate,
                                   '[label ci]' => for_name).sub('<p></p>', '')
      html += r[:template]
    end
    html
  end

  def cama_form_select_multiple_bootstrap(ob, title, type, values)
    # Defensive, because a form saved before the gate required a well-formed option list carries
    # whatever it carries -- and `nil.each`, or `op[:label]` on a String, is a 500 on every visit to
    # the page. `Array()` alone will not do: on a Hash it yields key/value pairs.
    raw_options = ob[:field_options][:options]
    options = (raw_options.is_a?(Hash) ? raw_options.values : Array(raw_options))
              .select { |op| op.is_a?(Hash) }
    include_other_option = ob[:field_options][:include_other_option]
    other_input = ''

    f_name = "fields[#{ob[:cid]}]"
    cid = ob[:cid].to_sym
    html = ''

    custom_class = ob[:custom_class].to_s

    if %w[radio checkbox].include?(type)
      other_input = if include_other_option
                      "<div class=\"#{type} #{custom_class}\"> <label for=\"#{ob[:cid]}\">" \
                      "<input id=\"#{ob[:cid]}-other\" type=\"#{type}\" name=\"#{title.downcase}[]\" class=\"\">" \
                      'Other <input type="text" /></label></div>'
                    else
                      ' '
                    end
    else
      html = "<select #{cf_attrs(ob[:custom_attrs])} name=\"#{f_name}\" class=\"#{custom_class}\">"
    end

    options.each do |op|
      label = op[:label].to_s.translate
      if %w[radio checkbox].include?(type)
        input_tag = "<input #{cf_attrs(ob[:custom_attrs])} type=\"#{type}\" " \
                    "#{'checked' if op[:checked].to_s.cama_true?} name=\"#{f_name}[]\" " \
                    "class=\"\" value=\"#{label.downcase}\">"
        html += "<div class=\"#{type} #{custom_class}\">
                    <label for=\"#{ob[:cid]}\">
                      #{input_tag}
                      #{label}
                    </label>
                  </div>"
      else
        # A dropdown submits the label lowercased with spaces collapsed to underscores. Derived once
        # so the emitted value and the `selected` comparison cannot drift apart -- but only here:
        # radio and checkbox have always submitted the plain lowercased label, and unifying the two
        # would silently change what every existing response row is compared against.
        option_value = label.downcase.tr(' ', '_')
        html += "<option  value=\"#{option_value}\" " \
                "#{'selected' if option_value == values[cid] || op[:checked].to_s.cama_true?} >#{label}</option>"
      end
    end

    html += if %w[radio checkbox].include?(type)
              other_input
            else
              ' </select>'
            end
  end
end
