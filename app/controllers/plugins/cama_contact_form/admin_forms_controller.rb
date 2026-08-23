# frozen_string_literal: true

# Admin CRUD for a site's contact forms; refuses (never rewrites) authored markup an untrusted role
# is not permitted to store.
class Plugins::CamaContactForm::AdminFormsController < CamaleonCms::Apps::PluginsAdminController
  include Plugins::CamaContactForm::MainHelper
  include Plugins::CamaContactForm::ContactFormControllerConcern

  before_action :set_form, only: %w[show edit update destroy]
  add_breadcrumb I18n.t('plugins.cama_contact_form.title', default: 'Contact Form'),
                 :admin_plugins_cama_contact_form_admin_forms_path

  def index
    @forms = current_site.contact_forms.where(parent_id: nil).all
    @forms = @forms.paginate(page: params[:page], per_page: current_site.admin_per_page)
  end

  def show; end

  def edit
    add_breadcrumb I18n.t('plugins.cama_contact_form.edit_view', default: 'Edit contact form')
    render 'edit'
  end

  def create
    @form = current_site.contact_forms.new(params.require(:plugins_cama_contact_form_cama_contact_form).permit(:name,
                                                                                                               :slug))
    if @form.save
      flash[:notice] = t('.created', default: 'Created successfully').to_s
      redirect_to action: :edit, id: @form.id
    else
      flash[:error] = @form.errors.full_messages.join(', ')
      redirect_to action: :index
    end
  end

  def update
    form_params = params.require(:plugins_cama_contact_form_cama_contact_form).permit(:name, :slug)
    settings = { 'railscf_mail' => params[:railscf_mail],
                 'railscf_message' => permitted_messages,
                 'railscf_form_button' => params[:railscf_form_button],
                 recaptcha_site_key: params[:recaptcha_site_key],
                 recaptcha_secret_key: params[:recaptcha_secret_key] }

    # The shape of `params` is chosen by the client, not by the form editor, and every check below
    # indexes into it. Verified first, for everyone, so that nothing downstream -- here or in the
    # renderer -- has to cope with a String where it expected a Hash.
    if (malformed = first_malformed_shape_key(settings))
      return reject_save(t('.malformed_structure', field: malformed,
                                                   default: 'A field has a malformed %{field}. Nothing was saved.'))
    end

    fields = submitted_fields

    # Checked before the record is touched, so a rejected save leaves the form exactly as it was
    # rather than persisting the name and slug and dropping everything else.
    if (malformed = first_malformed_structural_key(fields))
      return reject_save(t('.malformed_structure', field: malformed,
                                                   default: 'A field has a malformed %{field}. Nothing was saved.'))
    end

    if !trusted_for_unfiltered_html? && (rejected = first_unpermitted_html_key(settings, fields))
      return reject_save(rejection_message(*rejected))
    end

    if @form.update(form_params)
      @form.update({ settings: settings.to_json, value: { fields: fields }.to_json })
      flash[:notice] = t('.updated_success', default: 'Updated successfully')
      redirect_to action: :edit, id: @form.id
    else
      edit
    end
  end

  def destroy
    flash[:notice] = t('.deleted', default: 'Destroyed successfully').to_s if @form.destroy
    redirect_to action: :index
  end

  def responses
    add_breadcrumb I18n.t('plugins.cama_contact_form.list_responses', default: 'Contact form records')
    @form = current_site.contact_forms.where({ id: params[:admin_form_id] }).first
    values = JSON.parse(@form.value).to_sym
    @op_fields = values[:fields].select { |field| relevant_field? field }
    @forms = current_site.contact_forms.where({ parent_id: @form.id })
    @forms = @forms.paginate(page: params[:page], per_page: current_site.admin_per_page)
  end

  def del_response
    response = current_site.contact_forms.find_by(id: params[:response_id])
    if response.present? && response.destroy
      flash[:notice] = t('.actions.msg_deleted', default: 'The response has been deleted').to_s
    end
    redirect_to action: :responses
  end

  def manual; end

  def item_field
    render partial: 'item_field', locals: { field_type: params[:kind], cid: params[:cid] }
  end

  # Values the author writes that reach the page verbatim. Nothing here is rewritten on save: an
  # author either holds :manage, :contact_form_unfiltered_html and their content is stored exactly as
  # written, or the save is rejected and they are told which field to fix.
  #
  # Two kinds of position, because they fail differently:
  #
  #   Markup positions reach the page as element content. Unsafe means the value is not markup this
  #   role may write, or is markup a browser would read differently from the way it was parsed here.
  #
  #   Attribute positions are interpolated by the renderer inside a double-quoted HTML attribute.
  #   Unsafe means only that the value contains a double quote. Angle brackets, ampersands and
  #   apostrophes are harmless there, so they are allowed.
  #
  # Which position a value lands in is fixed rather than inferred, because the field `template` is
  # authored too. `placeholder_in_tag?` refuses a template that puts `[ci]`, `[label ci]` or
  # `[descr ci]` inside a tag, so every substituted value is element content and every attribute in
  # the emitted markup is one the renderer wrote with double quotes. That rule binds everyone, not
  # just untrusted authors: without it a template written by a trusted author decides the context of
  # a value written by an untrusted one, and the table below stops being true.
  MARKUP_MAIL_KEYS = %w[previous_html after_html body body_answer subject subject_answer].freeze
  MARKUP_FIELD_KEYS = %w[label].freeze
  MARKUP_FIELD_OPTION_KEYS = %w[template description].freeze

  # `label` is also emitted into `name="..."` by the "other" input of a radio/checkbox group.
  ATTRIBUTE_FIELD_KEYS = %w[label].freeze
  ATTRIBUTE_FIELD_OPTION_KEYS = %w[field_class].freeze

  # Built with a symbol key by #update, unlike the string-keyed settings around it. It reaches the
  # page as `data-sitekey="..."`, which the recaptcha gem interpolates without escaping.
  ATTRIBUTE_SETTING_KEYS = %i[recaptcha_site_key].freeze

  # Mail values the code indexes or interpolates. Held to a scalar for everyone: `to_answer` reaches
  # `String#gsub` in the front controller and `subject` reaches the mailer, both after a response row
  # has already been persisted.
  MAIL_SCALAR_KEYS = %w[to subject body to_answer subject_answer body_answer
                        previous_html after_html].freeze

  # The field types whose default_value is redisplayed as textarea content rather than in a value
  # attribute, and the ones that carry a list of options. Kept in step with the renderer's `case`.
  TEXTAREA_FIELD_TYPES = %w[paragraph textarea].freeze
  OPTION_FIELD_TYPES = %w[radio checkboxes dropdown select].freeze

  # An attribute whose *name* is an event handler runs script whatever its value is. It breaks out of
  # nothing, so neither the name-shape check nor the double-quote check below can see it: `onfocus`
  # is a perfectly well-formed attribute name carrying a perfectly quote-free value.
  #
  # A blunt `on` prefix rather than a list of known handler names, which is what HTML sanitizers use:
  # the handler set grows with the platform, and a list that has fallen behind fails open.
  EVENT_HANDLER_ATTR_NAME = /\Aon/i
  HTML_ATTR_NAME = /\A[a-zA-Z_:][-a-zA-Z0-9_:.]*\z/

  # An attribute name is not enough on its own: `formaction` on a submit button, or `href` on a link,
  # executes whatever scheme its value names. These carry a URL, so their value gets a scheme check;
  # `style` is refused outright, because an untrusted author has no need of inline CSS and
  # `position:fixed` over the viewport is a UI-redressing primitive.
  URL_BEARING_ATTR_NAMES = %w[href src action formaction data poster srcdoc xlink:href
                              background dynsrc lowsrc].freeze
  REFUSED_ATTR_NAMES = %w[style].freeze
  URL_IGNORABLE_CHARS = /[[:space:]\u0000-\u001F\u007F]/
  DANGEROUS_URL_SCHEME = /\A(?:javascript|vbscript|data):/i

  # The safe list CamaleonCms::UnsafeMarkup scrubs these positions against: Rails' own, widened with
  # the layout elements these positions legitimately carry. Rails' list is tuned for prose and omits
  # `label`, `section`, `fieldset` and the table elements -- which is why the plugin's own default
  # template was refused by an earlier implementation.
  #
  # `rel` and `target` are deliberately NOT added. Rails omits them on purpose: `rel="opener"` is the
  # explicit opt-back-in to the `window.opener` handle that browsers disable for `target="_blank"`,
  # and it hands an untrusted author the ability to repoint the visitor's original tab.
  MARKUP_TAGS = (Rails::HTML5::SafeListSanitizer.allowed_tags +
                 %w[label section article header footer main aside nav figure figcaption
                    fieldset legend table caption colgroup col thead tbody tfoot tr td th
                    time mark wbr picture source]).freeze
  MARKUP_ATTRS = (Rails::HTML5::SafeListSanitizer.allowed_attributes +
                  %w[id for colspan rowspan span role tabindex hidden]).freeze

  # A well-formed translation marker (`<!--:-->`, `<!--:en-->`). `rendered_forms` strips these to
  # produce the marker-free string the renderer emits, so the gate judges that form too.
  TRANSLATION_MARKER = /<!--:[\w|-]{0,5}-->/

  PLACEHOLDER = /\[(?:ci|label ci|descr ci)\]/

  # One whole tag, quoted attribute values included, so a `>` written inside an attribute does not
  # look like the end of the tag. The closing quote is optional so an unterminated one runs to the
  # end of the value rather than ending the match early.
  TAG_SPAN = %r{<[a-zA-Z/!?][^"'>]*(?:(?:"[^"]*"?|'[^']*'?)[^"'>]*)*>?}

  # Structural values, as opposed to authored content: the form builder generates them and nobody
  # types markup into them. They are checked against an allowlist for *everyone*, including an author
  # holding the unfiltered-HTML grant -- a field whose type is `text" onfocus="x` is not a feature
  # anyone wants, it is a corrupt record. Constraining them here is what lets the renderer emit them
  # verbatim alongside everything else.
  # `select` is the legacy spelling of `dropdown`; a form stored under an older version carries it.
  FIELD_TYPES = %w[text paragraph textarea website email radio checkboxes dropdown select captcha file
                   submit button reset_button].freeze
  CID_FORMAT = /\A[a-zA-Z0-9_-]+\z/

  # Every gated value costs a parse, and both the number of values and their size are chosen by the
  # caller. Without these an account holding nothing but :manage, :plugins can drive several thousand
  # Loofah parses, or one multi-megabyte parse, from a single request.
  MAX_FIELDS = 200
  MAX_OPTIONS_PER_FIELD = 100
  MAX_GATED_VALUE_BYTES = 64 * 1024

  # The messages the form editor offers, plus `invalid_content`, which the gate itself emits.
  #
  # Permitted rather than taken wholesale. `railscf_message` used to go straight from params into the
  # gate, which runs a full Loofah parse per leaf -- so the number of parses was chosen by the caller.
  # Permitting also stops unbounded junk being persisted into `settings.to_json`.
  MESSAGE_KEYS = %w[mail_sent_ok mail_sent_ng validation_error invalid_required invalid_email
                    captcha_not_match invalid_content].freeze

  private

  # Mirrors CamaleonCms::Post#trusted_for_unfiltered_html?: read the acting user and site from
  # CurrentRequest and fail closed when either is missing, so saves from background jobs, rake tasks
  # or the console are treated as untrusted. The site is guarded as well because Ability#initialize
  # dereferences it for non-admin users and would otherwise raise mid-save.
  def trusted_for_unfiltered_html?
    user = CurrentRequest.user
    site = CurrentRequest.site
    return false if user.blank? || site.blank?

    CamaleonCms::Ability.new(user, site).can?(:manage, :contact_form_unfiltered_html)
  end

  # Normalizes the submitted fields into the list that is stored. Shape is already known good --
  # `first_malformed_shape_key` refuses a non-hash field or field_options rather than dropping it,
  # so nothing here silently discards what the author typed.
  def submitted_fields
    raw = params[:fields]
    return [] unless hashish?(raw)

    raw.each_value.map do |v|
      options = at(v, :field_options)
      v[:field_options] = options = ActionController::Parameters.new if options.blank?
      options[:options] = options[:options].values if hashish?(options[:options])
      v
    end
  end

  # Returns `[name, rule]` for the first value an untrusted author may not save, or nil.
  #
  # `name` is only ever a key from the lists above -- never the value, and never the field's label.
  # The message built from it is rendered with `raw` by Camaleon's admin flash partial, so echoing
  # back the content that was just rejected would make the rejection itself an injection sink.
  #
  # `rule` names which test refused it, so the message can say what to remove. Telling an author who
  # typed `btn "primary"` into Custom Class that it "contains HTML" sends them looking for markup
  # that is not there, and points them at a permission that would not have applied.
  #
  # Stops at the first offender rather than collecting them all: nothing is saved either way.
  def first_unpermitted_html_key(settings, fields)
    mail = settings['railscf_mail']
    MARKUP_MAIL_KEYS.each { |k| return [k, :markup] if unsafe_markup?(at(mail, k)) }
    return ['submit button label', :markup] if unsafe_markup?(at(settings['railscf_form_button'], 'name_button'))
    return ['response message', :markup] if unsafe_messages?(settings['railscf_message'])

    ATTRIBUTE_SETTING_KEYS.each { |k| return [k.to_s, :attribute] if unsafe_attribute?(settings[k]) }

    fields.each do |field|
      MARKUP_FIELD_KEYS.each { |k| return [k, :markup] if unsafe_markup?(at(field, k)) }
      ATTRIBUTE_FIELD_KEYS.each { |k| return [k, :attribute] if unsafe_attribute?(at(field, k)) }
      if (rule = unsafe_default_value_rule(field))
        return ['default_value', rule]
      end

      options = at(field, :field_options)
      next if options.blank?

      MARKUP_FIELD_OPTION_KEYS.each { |k| return [k, :markup] if unsafe_markup?(at(options, k)) }
      ATTRIBUTE_FIELD_OPTION_KEYS.each { |k| return [k, :attribute] if unsafe_attribute?(at(options, k)) }
      return ['field_attributes', :attributes_json] if unsafe_attribute_json?(at(options, 'field_attributes'))

      # An option label reaches BOTH positions no matter what the template says: it is element
      # content inside the `<label>`, and the renderer also derives the control's `value="..."`
      # from it. So it carries both rules, unlike `description`, which the template can only ever
      # place as element content.
      Array(at(options, :options)).each do |option|
        label = at(option, 'label')
        return ['option label', :markup] if unsafe_markup?(label)
        return ['option label', :attribute] if unsafe_attribute?(label)
      end
    end

    nil
  end

  # Reads a key only from something that actually has keys. `try(:[], k)` looked equivalent and was
  # not: on a String it reaches `String#[]`, which is substring search, so a scalar submitted where a
  # hash was expected returned nil and every check on it reported safe.
  def at(container, key)
    return nil unless hashish?(container)

    container[key]
  end

  def hashish?(value)
    value.is_a?(Hash) || value.is_a?(ActionController::Parameters)
  end

  def scalarish?(value)
    value.nil? || value.is_a?(String) || value.is_a?(Numeric)
  end

  def oversized?(value)
    value.to_s.bytesize > MAX_GATED_VALUE_BYTES
  end

  # Refusals use flash.now, not flash: this renders rather than redirecting, so a plain flash would
  # survive into the *next* page the author visits and report a failure that is no longer happening.
  #
  # Everything the author typed is carried back, so a refused save does not discard their work. The
  # record is assigned but never saved, and `#fields`/`#the_settings` memoize off the assigned
  # attributes, so `edit.html.erb` redraws the submitted form rather than the stored one.
  def reject_save(message)
    flash.now[:error] = message
    @form.assign_attributes(name: params.dig(:plugins_cama_contact_form_cama_contact_form, :name),
                            slug: params.dig(:plugins_cama_contact_form_cama_contact_form, :slug))
    repopulate_editor
    edit
  end

  # Normalized to the shape `edit.html.erb` reads, not handed back raw: these are by definition the
  # params that just failed validation, so a field may be a bare string or an option list a hash.
  # A malformed field is dropped from the redraw rather than crashing it -- the message already names
  # what was wrong with it. Best effort throughout: a refusal is never worth a second exception.
  def repopulate_editor
    submitted = params[:fields]
    if hashish?(submitted)
      redrawn = submitted.each_value.select { |field| hashish?(field) }.map do |field|
        field = field.to_unsafe_h.dup if field.respond_to?(:to_unsafe_h)
        options = field[:field_options]
        field[:field_options] = hashish?(options) ? options : {}
        field
      end
      @form.value = { fields: redrawn }.to_json
    end
    @form.settings = { 'railscf_mail' => params[:railscf_mail],
                       'railscf_message' => params[:railscf_message],
                       'railscf_form_button' => params[:railscf_form_button],
                       recaptcha_site_key: params[:recaptcha_site_key],
                       recaptcha_secret_key: params[:recaptcha_secret_key] }.to_json
  rescue StandardError
    nil
  end

  def rejection_message(rejected, rule)
    case rule
    when :attribute
      t('.unsafe_attribute_rejected', field: rejected,
                                      default: 'The %{field} contains a double quote, which would break the HTML ' \
                                               'attribute it is written into. Nothing was saved. Remove it, or ask ' \
                                               'an administrator to grant the "Allow unfiltered HTML in contact ' \
                                               'forms" permission.')
    when :textarea
      t('.unsafe_textarea_rejected', field: rejected,
                                     default: 'The %{field} closes the text box it is written into. Nothing was ' \
                                              'saved. Remove the closing tag, or ask an administrator to grant the ' \
                                              '"Allow unfiltered HTML in contact forms" permission.')
    when :attributes_json
      t('.unsafe_attributes_rejected', field: rejected,
                                       default: 'The %{field} contains an attribute your role is not permitted to ' \
                                                'save: an event handler, an inline style, a script URL, or a ' \
                                                'malformed name. Nothing was saved. Remove it, or ask an ' \
                                                'administrator to grant the "Allow unfiltered HTML in contact forms" ' \
                                                'permission.')
    else
      t('.unfiltered_html_rejected', field: rejected,
                                     default: 'The %{field} contains HTML that your role is not permitted to save. ' \
                                              'Nothing was saved. Remove it, or ask an administrator to grant the ' \
                                              '"Allow unfiltered HTML in contact forms" permission.')
    end
  end

  # The containers the gate and the renderer both index into. Checked for everyone, before anything
  # else, because a wrong shape here is not an authoring mistake to be judged by permission -- it is
  # a record neither side can read. A missing container is fine (a partial update leaves it unset,
  # and the model's readers default it); a container of the wrong type is not.
  def first_malformed_shape_key(settings)
    # `nil?`, not `blank?`: an absent `fields` means the caller is not editing them, but an empty
    # string is a shape the editor never sends -- and `("" || {}).each` is a NoMethodError, because
    # `""` is truthy.
    fields_param = params[:fields]
    return 'form fields' unless fields_param.nil? || hashish?(fields_param)

    if hashish?(fields_param)
      return 'field count' if fields_param.keys.size > MAX_FIELDS

      fields_param.each_value do |field|
        return 'form field' unless hashish?(field)

        options = at(field, :field_options)
        return 'field options' unless options.blank? || hashish?(options)
      end
    end

    { 'railscf_mail' => 'mail settings', 'railscf_message' => 'response message',
      'railscf_form_button' => 'submit button label' }.each do |key, name|
      value = settings[key]
      return name unless value.nil? || hashish?(value)
    end

    MAIL_SCALAR_KEYS.each do |key|
      value = at(settings['railscf_mail'], key)
      return key unless scalarish?(value)
      return key if oversized?(value)
    end

    button = at(settings['railscf_form_button'], 'name_button')
    return 'submit button label' unless scalarish?(button)
    return 'submit button label' if oversized?(button)

    each_leaf(settings['railscf_message']) { |v| return 'response message' if oversized?(v) }

    ATTRIBUTE_SETTING_KEYS.each do |key|
      return key.to_s unless settings[key].blank? || settings[key].is_a?(String)
      return key.to_s if oversized?(settings[key])
    end

    nil
  end

  # default_value lands in whichever position its field type renders: a paragraph or textarea
  # redisplays it as textarea content, every other type puts it in a double-quoted value attribute.
  # Sound only because `placeholder_in_tag?` guarantees `[ci]` is element content -- otherwise a
  # template of `<div title="[ci]">` puts the whole textarea inside an attribute and neither rule
  # describes the position. Returns the rule that refused it, or nil.
  def unsafe_default_value_rule(field)
    value = at(field, 'default_value')
    if TEXTAREA_FIELD_TYPES.include?(at(field, :field_type).to_s)
      unsafe_textarea?(value) ? :textarea : nil
    else
      unsafe_attribute?(value) ? :attribute : nil
    end
  end

  def permitted_messages
    messages = params[:railscf_message]
    return messages unless messages.respond_to?(:permit)

    messages.permit(*MESSAGE_KEYS)
  end

  # Every railscf_message value reaches the public page. The front controller joins them into
  # flash[:contact_form] on both the failure and the success path, and the frontend flash partial
  # renders that with `raw`.
  def unsafe_messages?(messages)
    each_leaf(messages).any? { |value| unsafe_markup?(value) }
  end

  # Lazy, so the first offending leaf stops the walk.
  def each_leaf(value, &block)
    return enum_for(:each_leaf, value) unless block

    case value
    when ActionController::Parameters, Hash then value.each_value { |v| each_leaf(v, &block) }
    when Array then value.each { |v| each_leaf(v, &block) }
    else yield value
    end
  end

  # Returns the name of the first malformed structural value, or nil. Same rule: the key only, never
  # the value the author submitted.
  def first_malformed_structural_key(fields)
    fields.each do |field|
      return 'cid' unless at(field, :cid).to_s.match?(CID_FORMAT)

      type = at(field, :field_type).to_s
      return 'field type' unless FIELD_TYPES.include?(type)
      return 'required flag' unless scalarish?(at(field, :required))

      options = at(field, :field_options)
      maxlength = at(options, 'maxlength')
      return 'maxlength' if maxlength.present? && !maxlength.to_s.match?(/\A\d+\z/)

      option_list = Array(at(options, :options))
      return 'option count' if option_list.size > MAX_OPTIONS_PER_FIELD

      # A field type that renders a list of choices needs at least one, and every option needs a
      # label: `options.each` and `op[:label].translate` are both unguarded in the renderer, so
      # either omission is a NoMethodError on every visit, from a save the author was told succeeded.
      return 'options' if OPTION_FIELD_TYPES.include?(type) && option_list.empty?

      option_list.each do |option|
        return 'option label' unless hashish?(option) && at(option, 'label').is_a?(String)
        return 'option label' if oversized?(at(option, 'label'))
      end

      # Every substituted slot must be a string for the same reason: `["<div>[ci]</div>"].to_s` is
      # sanitize-stable, so an array-valued template passes the content gate and then reaches
      # `String#sub` in the renderer.
      (MARKUP_FIELD_KEYS + ATTRIBUTE_FIELD_KEYS + %w[default_value]).each do |k|
        return k unless scalarish?(at(field, k))
        return k if oversized?(at(field, k))
      end
      (MARKUP_FIELD_OPTION_KEYS + ATTRIBUTE_FIELD_OPTION_KEYS + %w[field_attributes]).each do |k|
        return k unless scalarish?(at(options, k))
        return k if oversized?(at(options, k))
      end

      # Binds everyone, including a grant holder. A placeholder inside a tag makes the substituted
      # value's HTML context depend on who wrote the template rather than on what the value is, and
      # `field_attributes` that is not a JSON object reaches `{id: cid}.merge(...)` in the renderer
      # and raises TypeError on every public page.
      return 'template' if placeholder_in_tag?(at(options, 'template'))
      return 'field_attributes' if malformed_attribute_json?(at(options, 'field_attributes'))
    end

    nil
  end

  # Every gated value is checked in each of the forms it can reach the page as, not only as written.
  # `String#translate` picks a locale-specific substring and *deletes* the `<!--:xx-->` markers on the
  # way, so the renderer emits a string the gate never saw. Checking only the stored form let an
  # author split a payload across a marker -- `</tex<!--:en-->tarea>` -- and have the renderer put it
  # back together.
  def rendered_forms(value)
    string = value.to_s
    return [] if string.blank?

    ([string] + string.translations_array.map(&:to_s) + [string.gsub(TRANSLATION_MARKER, '')]).uniq
  rescue StandardError
    [string]
  end

  # Each rendered form is judged by CamaleonCms::UnsafeMarkup, the core scan-and-reject detector this
  # gate is kept in parity with. It parses once and refuses the value when the safe-list scrubber
  # would remove anything, when a kept attribute smuggles markup (`title="&lt;img ...&gt;"` reaching a
  # `data-html` sink), when dangerous inline CSS survives, or when the value carries one of the
  # structural shapes an HTML parser silently repairs -- an unterminated tag or attribute, a
  # foster-parented table cell, a translation marker inside a tag. MARKUP_TAGS/MARKUP_ATTRS widen
  # Rails' safe list with the layout elements these positions carry; `data-`/`aria-` attributes are
  # admitted by shape by the detector itself.
  def unsafe_markup?(value)
    rendered_forms(value).any? do |form|
      CamaleonCms::UnsafeMarkup.unsafe_html?(form, tags: MARKUP_TAGS, attributes: MARKUP_ATTRS)
    end
  end

  # A template must not put one of the renderer's own placeholders inside a tag: doing so decides the
  # HTML context of a value written somewhere else, possibly by someone else. Structural rather than
  # parse-based (see token_inside_tag?), because an HTML parser silently repairs the shape.
  def placeholder_in_tag?(value)
    string = value.to_s
    return false unless string.include?('[')

    token_inside_tag?(string, PLACEHOLDER)
  end

  # Collects the value's tags and reports whether `token` appears inside any of them. Structural
  # rather than parse-based, because an HTML parser silently repairs both of the shapes this exists
  # to catch. `token` is listed first in the alternation so a token standing on its own is consumed
  # as itself and not mistaken for a tag; one swallowed by a real tag span is not.
  def token_inside_tag?(string, token)
    tags = +''
    string.scan(/#{token}|#{TAG_SPAN}/) { |match| tags << match unless match.match?(/\A#{token}\z/) }
    tags.match?(token)
  end

  def unsafe_attribute?(value)
    rendered_forms(value).any? { |form| form.include?('"') }
  end

  # RCDATA: only the closing tag ends a textarea, so that sequence is the whole of what is refused.
  # Quotes, ampersands and angle brackets are ordinary characters in a prefilled message.
  def unsafe_textarea?(value)
    rendered_forms(value).any? { |form| form.downcase.include?('</textarea') }
  end

  # Valid JSON that is not an object. Structural, because the renderer's `rescue {}` binds only to
  # `JSON.parse`, so a well-formed `[1,2]` parses, reaches `{id: cid}.merge(...)` and raises
  # TypeError -- a permanent 500 on every public page, from a save reported as successful. Held to
  # everyone, grant holders included: it is a corrupt record, not a capability.
  def malformed_attribute_json?(value)
    return false if value.blank?

    parsed = parse_attribute_json(value)
    return false if parsed == :unparseable

    !parsed.is_a?(Hash)
  end

  # field_attributes is a JSON object emitted verbatim as attribute name/value pairs, so an untrusted
  # author may write neither a name that escapes the tag nor one that is itself script:
  #
  #   a name that is not a valid attribute name renders as several attributes;
  #   a value containing a double quote closes its own;
  #   a name beginning with `on` is an event handler and runs whatever the value says;
  #   a name carrying a URL executes whatever scheme that URL names;
  #   `style` is refused outright, being enough on its own to cover the viewport with an overlay.
  def unsafe_attribute_json?(value)
    return false if value.blank?

    parsed = parse_attribute_json(value)
    return false unless parsed.is_a?(Hash)

    parsed.any? { |k, v| unsafe_attribute_pair?(k, v) }
  end

  def parse_attribute_json(value)
    JSON.parse(value.to_s)
  rescue StandardError
    :unparseable
  end

  def unsafe_attribute_pair?(name, value)
    name = name.to_s
    return true unless name.match?(HTML_ATTR_NAME)
    return true if name.match?(EVENT_HANDLER_ATTR_NAME)
    return true if REFUSED_ATTR_NAMES.include?(name.downcase)
    return true if value.to_s.include?('"')

    URL_BEARING_ATTR_NAMES.include?(name.downcase) && dangerous_url?(value)
  end

  # Decoded the way the browser will decode it. `CGI.unescapeHTML` handles only the five legacy
  # entities and numeric references, so `javascript&colon;alert(1)` and `java&Tab;script:alert(1)`
  # walked straight past a hand-rolled check -- and the HTML parser resolves both to `javascript:`.
  # The parser is the authority on that question, so it is the one asked. The value is known to
  # carry no double quote by the time this runs.
  def dangerous_url?(value)
    decoded = Loofah.html5_fragment(%(<a href="#{value}">)).at_css('a')&.[]('href').to_s
    decoded.gsub(URL_IGNORABLE_CHARS, '').match?(DANGEROUS_URL_SCHEME)
  end

  def set_form
    @form = current_site.contact_forms.find_by(id: params[:id])
  rescue StandardError
    flash[:error] = t('.error_form_class', default: 'Error form class')
    redirect_to cama_admin_path
  end
end
