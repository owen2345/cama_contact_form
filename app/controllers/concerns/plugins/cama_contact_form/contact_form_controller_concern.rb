# frozen_string_literal: true

require 'uri'

# Contact-form logic shared by the admin and front controllers: it gates authored markup at save
# time, and validates, stores and mails a visitor's submission.
module Plugins::CamaContactForm::ContactFormControllerConcern
  # The field types whose submitted value the renderer interpolates back into the page, and the
  # position each one lands in. Everything else -- radio, checkboxes, dropdown, file -- is only ever
  # compared against, never interpolated, so nothing it contains can escape anything.
  ECHOED_ATTRIBUTE_FIELD_TYPES = %w[text website email].freeze
  ECHOED_TEXTAREA_FIELD_TYPES = %w[paragraph textarea].freeze

  # Field types whose submitted value is a list of chosen option labels, joined for the mail summary.
  MULTI_VALUE_FIELD_TYPES = %w[radio checkboxes].freeze

  # Elements that do something rather than say something, wherever they appear.
  ACTIVE_ELEMENTS = %w[script style iframe object embed applet frame frameset form input button
                       link meta base svg math template].freeze
  ACTIVE_ELEMENT = %r{<\s*/?\s*(?:#{ACTIVE_ELEMENTS.join('|')})\b}i
  EVENT_HANDLER_IN_TAG = /<[a-zA-Z][^>]*\son[a-zA-Z]+\s*=/im
  URL_SCHEME_IN_TAG =
    /<[a-zA-Z][^>]*\b(?:href|src|action|formaction|data|poster|srcdoc|background)\s*=\s*
       ["']?\s*(?:javascript|vbscript|data)\s*:/imx

  def perform_save_form(form, fields, success, errors)
    attachments = []
    return unless validate_to_save_form(form, fields, errors)

    form.fields.each do |f|
      next unless f[:field_type] == 'file'

      file_paths = []
      fields[f[:cid].to_sym].to_a.each do |file|
        res = cama_tmp_upload(file, {
                                maximum: current_site.get_option('filesystem_max_size', 100).megabytes,
                                path: Rails.public_path.join('contact_form', current_site.id.to_s),
                                name: file.original_filename
                              })
        if res[:error].present?
          errors << res[:error].to_s.translate
        else
          attachments << res[:file_path]
          file_paths << res[:file_path].sub(Rails.public_path.to_s, cama_root_url)
        end
      end
      fields[f[:cid].to_sym] = file_paths
    end
    new_settings = { 'fields' => fields, 'created_at' => Time.now.utc.strftime('%Y-%m-%d %H:%M:%S').to_s }.to_json
    form_new = current_site.contact_forms.new(name: "response-#{Time.now.utc}", description: form.description,
                                              settings: new_settings, site_id: form.site_id, parent_id: form.id)
    if form_new.save
      fields_data = convert_form_values(form, fields)
      message_body = form.mail_settings[:body].to_s.translate.cama_replace_codes(fields)
      content = render_to_string(partial: plugin_view('contact_form/email_content'), layout: false, formats: [:html],
                                 locals: { file_attachments: attachments, fields: fields_data, values: fields,
                                           message_body: message_body, form: form })
      cama_send_email(form.mail_settings[:to],
                      form.mail_settings[:subject].to_s.translate.cama_replace_codes(fields),
                      { attachments: attachments, content: content, extra_data: { fields: fields_data } })
      success << form.the_message('mail_sent_ok',
                                  t('.success_form_val',
                                    default: 'Your message has been sent successfully. Thank you very much!'))
      args = { form: form, values: fields }
      hooks_run('contact_form_after_submit', args)
      if (answer_to = auto_reply_recipient(form, fields))
        content = form.mail_settings[:body_answer].to_s.translate.cama_replace_codes(fields)
        cama_send_email(answer_to, form.mail_settings[:subject_answer].to_s.translate.cama_replace_codes(fields),
                        { content: content })
      end
    else
      errors << form.the_message('mail_sent_ng',
                                 t('.error_form_val', default: 'An error occurred, please try again.'))
    end
  end

  # CF-1: the auto-reply ("confirmation e-mail") recipient is whatever the visitor typed into the field
  # named by `to_answer`, so it is fully attacker-controlled -- unchecked, the feature sends mail from
  # the site's own From address to anyone. The reply goes to the normalized address, or nowhere.
  # Volume across submissions is a separate concern (CF-2, rate limiting).
  #
  # A refused present value is logged -- otherwise the response is indistinguishable from full
  # success and a lost confirmation is undiagnosable. The line names the form, not the value: the
  # value is hostile by hypothesis, and hostile bytes don't belong in the log stream. An absent or
  # blank value stays silent, as it always has -- the visitor supplied nothing to refuse.
  def auto_reply_recipient(form, fields)
    return if form.mail_settings[:to_answer].blank?

    value = fields[form.mail_settings[:to_answer].to_s.gsub(/(\[|\])/, '').to_sym]
    address = normalized_email_address(value)
    if address.nil? && value.present?
      Rails.logger.warn("cama_contact_form: auto-reply for form #{form.id} skipped, recipient failed validation (CF-1)")
    end
    address
  end

  # The stripped value when it is a single, syntactically-valid address; nil otherwise. Surrounding
  # whitespace is stripped -- a pasted or mobile-typed address often carries a stray space, and the
  # mailer delivered those before this guard existed -- and what remains must match
  # `URI::MailTo::EMAIL_REGEXP`, which is anchored and admits no CR/LF, inner whitespace or `,`/`;`,
  # so one submission can neither header-inject a Bcc nor fan out to a recipient list. Refused with
  # the attacks, deliberately: name-addr forms (`Jane <jane@example.com>` -- address lists share that
  # grammar) and raw-unicode addresses (the regexp is ASCII-only; the punycode form passes). A
  # non-String value (`fields[cid][]=…` arrives as an Array) is rejected through `to_s` rather than
  # raising.
  def normalized_email_address(value)
    address = value.to_s.strip
    address if address.match?(URI::MailTo::EMAIL_REGEXP)
  end

  # A visitor's submission is rejected, not escaped, for the same reason an untrusted author's is:
  # what is stored and redisplayed then equals what was submitted, so rendering it verbatim adds
  # nothing.
  #
  # Memoized because both the validation and the redisplay decision ask the same question about the
  # same two objects in a single request, and the walk is over attacker-chosen structure.
  def unsafe_submitted?(form, fields)
    return @_cf_unsafe_submitted unless @_cf_unsafe_submitted.nil?

    @_cf_unsafe_submitted = compute_unsafe_submitted?(form, fields)
  end

  # Fails closed on a missing form: there is nothing to judge the submission against, and the caller
  # must not go on to stash it.
  def compute_unsafe_submitted?(form, fields)
    return true if form.blank?
    return true unless fields.is_a?(Hash) || fields.is_a?(ActionController::Parameters)

    form.fields.any? { |f| unsafe_submitted_field?(f, fields[f[:cid].to_sym]) }
  end

  # Two sinks, judged separately because they are different contexts:
  #
  #   The notification e-mail interpolates every submitted value into an author-written body and
  #   renders the result with `raw`, so a value carrying active markup is refused whatever its type.
  #   The test is deliberately narrow -- script, an event handler, a script URL -- and not a
  #   sanitizer, which would reject ordinary prose: a visitor writing `Fish & Chips <today>` would be
  #   told their message is not allowed, which is both wrong and infuriating.
  #
  #   The redisplayed form interpolates the value only for the types listed above, and only into a
  #   double-quoted value attribute or into `<textarea>` content. A paragraph is RCDATA, where markup
  #   is literal text and only the closing tag ends it, so quotes and angle brackets are ordinary
  #   characters there.
  def unsafe_submitted_field?(field, value)
    return false if value.blank?
    return true if submitted_leaves(value).any? { |leaf| active_markup?(leaf) }

    type = field[:field_type].to_s
    if ECHOED_TEXTAREA_FIELD_TYPES.include?(type)
      echoed_value(value).downcase.include?('</textarea')
    elsif ECHOED_ATTRIBUTE_FIELD_TYPES.include?(type)
      echoed_value(value).include?('"')
    else
      false
    end
  end

  # The exact string the renderer will emit. `values[cid]` is interpolated directly, so a non-String
  # is judged by its `to_s` -- which is how an Array or a Hash supplies the double quote that closes
  # the attribute without the payload needing one of its own. Judging the leaves instead of the whole
  # missed that; judging `Array#to_s` for *every* type refused every checkbox and every file upload,
  # because `Array#to_s` is `inspect` and always carries quotes.
  def echoed_value(value)
    value.is_a?(String) ? value : value.to_s
  end

  # An uploaded file is not redisplayed and has no string form worth inspecting; everything else is
  # judged as the mail body will interpolate it.
  def submitted_leaves(value)
    case value
    when ActionController::Parameters then submitted_leaves(value.to_unsafe_h)
    when Hash then value.values.flat_map { |v| submitted_leaves(v) }
    when Array then value.flat_map { |v| submitted_leaves(v) }
    when ActionDispatch::Http::UploadedFile then []
    else [value.to_s]
    end
  end

  def active_markup?(string)
    string = string.to_s
    return false unless string.include?('<')

    string.match?(ACTIVE_ELEMENT) || string.match?(EVENT_HANDLER_IN_TAG) || string.match?(URL_SCHEME_IN_TAG)
  end

  # form validations
  def validate_to_save_form(form, fields, errors)
    # Refuse outright and stop, before any other validation runs.
    #
    # Nothing is stored either way, so there is nothing to gain by continuing -- and continuing means
    # running the rest of this method over input already known to be hostile, including a reCAPTCHA
    # round-trip to an external service.
    #
    # The message names no field and quotes nothing back. The frontend flash partial renders with
    # `raw`, so echoing the refused value there would make the refusal itself an injection sink --
    # the same trap as the admin path.
    if form.blank? || !(fields.is_a?(Hash) || fields.is_a?(ActionController::Parameters))
      errors << t('.invalid_request_val', default: 'That form could not be submitted. Please try again.')
      return false
    end

    if unsafe_submitted?(form, fields)
      errors << form.the_message('invalid_content',
                                 t('.invalid_content_val',
                                   default: 'Your message contains characters that are not allowed. ' \
                                            'Please remove any HTML or quotation marks and try again.'))
      return false
    end

    validate = true

    form.fields.each do |f|
      cid = f[:cid].to_sym
      label = f[:label].to_sym
      case f[:field_type].to_s
      when 'text', 'website', 'paragraph', 'textarea', 'email', 'radio', 'checkboxes', 'dropdown', 'file'
        if f[:required].to_s.cama_true? && fields[cid].blank?
          errors << "#{label.to_s.translate}: #{form.the_message('invalid_required',
                                                                 t('.error_validation_val',
                                                                   default: 'This value is required'))}"
          validate = false
        end
        # Judged by the same rule as the auto-reply recipient (`normalized_email_address`, which is
        # total on any submitted shape -- the submitter chooses whether to send the key at all, and
        # in what shape), so the field validation and the send decision cannot disagree: a malformed
        # address is an error the visitor can act on here, not a success message followed by a
        # confirmation that silently never arrives.
        if (f[:field_type].to_s == 'email') && normalized_email_address(fields[cid]).nil?
          errors << "#{label.to_s.translate}: #{form.the_message('invalid_email',
                                                                 t('.email_invalid_val',
                                                                   default: 'The e-mail address appears invalid'))}"
          validate = false
        end
      when 'captcha'
        error_message = lambda {
          errors << "#{label.to_s.translate}: #{form.the_message('captcha_not_match',
                                                                 t('.captch_error_val',
                                                                   default: 'The entered code is incorrect'))}"
          validate = false
        }

        if form.recaptcha_enabled?
          form.set_captcha_settings!
          error_message.call unless verify_recaptcha
        else
          error_message.call unless cama_captcha_verified?
        end
      end
    end
    validate
  end

  # form values with labels + values to save
  def convert_form_values(form, fields)
    values = {}
    form.fields.each do |field|
      next unless relevant_field?(field)

      ft = field[:field_type]
      cid = field[:cid].to_sym
      label = values.key?(field[:label]) ? "#{field[:label]} (#{cid})" : field[:label].to_s.translate
      values[label] = []
      if ft == 'file'
        nr_files = Array(fields[cid]).size
        values[label] << "#{nr_files} #{'file'.pluralize(nr_files)} (attached)" if fields[cid].present?
      elsif MULTI_VALUE_FIELD_TYPES.include?(ft)
        values[label] << Array(fields[cid]).map { |f| f.to_s.translate }.join(', ') if fields[cid].present?
      elsif fields[cid].present?
        values[label] << fields[cid]
      end
    end
    values
  end

  def relevant_field?(field)
    %w[captcha submit button].exclude?(field[:field_type])
  end
end
