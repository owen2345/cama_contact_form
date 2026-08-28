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

  # Elements that do something rather than say something, wherever they appear. `img` sits with the
  # other external-resource loaders (`iframe`, `object`, `embed`): the notification e-mail renders a
  # visitor's value with `raw`, so `<img src="http://attacker/">` there is a tracking beacon that
  # fetches an attacker URL -- leaking that the owner opened the mail, and their IP -- the moment
  # they open it, which no contact message legitimately needs. Ordinary prose with angle brackets
  # (`Fish & Chips <today>`) is an unknown tag, not one of these, so it still passes.
  ACTIVE_ELEMENTS = %w[script style iframe object embed img applet frame frameset form input button
                       link meta base svg math template].freeze
  ACTIVE_ELEMENT = %r{<\s*/?\s*(?:#{ACTIVE_ELEMENTS.join('|')})\b}i
  EVENT_HANDLER_IN_TAG = /<[a-zA-Z][^>]*\son[a-zA-Z]+\s*=/im
  URL_SCHEME_IN_TAG =
    /<[a-zA-Z][^>]*\b(?:href|src|action|formaction|data|poster|srcdoc|background)\s*=\s*
       ["']?\s*(?:javascript|vbscript|data)\s*:/imx

  # How many submissions one client IP may make to one form before the excess is refused, and the
  # window that count rolls off over. The threshold is the site-wide `contact_form_max_submits` option
  # (it tunes every form on the site at once, not one form); the window is camaleon_cms's own login
  # throttle window, shared as one constant so the two cannot drift.
  SUBMISSION_THROTTLE_WINDOW = CamaleonCms::CaptchaHelper::CAMA_ATTACK_WINDOW
  SUBMISSION_THROTTLE_DEFAULT_MAX = 10

  # How many files one submission may attach across all of its file fields, before the whole
  # submission is refused. Core bounds each file's size (`filesystem_max_size`); this bounds the
  # count, so the two together bound what one anonymous POST can write to disk and stuff into the
  # notification mail. The site-wide `contact_form_max_files` option overrides it.
  ATTACHMENT_COUNT_DEFAULT_MAX = 5

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
    # The random suffix keeps concurrent responses distinct: stamped only to the second, two visitors
    # submitting within the same second parameterized to the same slug, and the site-scoped
    # slug-uniqueness validation refused the second response with the generic error.
    form_new = current_site.contact_forms.new(name: "response-#{Time.now.utc}-#{SecureRandom.hex(4)}",
                                              description: form.description,
                                              settings: new_settings, site_id: form.site_id, parent_id: form.id)
    if form_new.save
      record_submission(form)
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

  # The auto-reply ("confirmation e-mail") recipient is whatever the visitor typed into the field
  # named by `to_answer`, so it is fully attacker-controlled -- unchecked, the feature sends mail from
  # the site's own From address to anyone. The reply goes to the normalized address, or nowhere.
  # Volume across submissions is a separate concern (rate limiting, below).
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
      Rails.logger.warn("cama_contact_form: auto-reply for form #{form.id} skipped, recipient failed validation")
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

  # Whether this client IP has already used up its budget for this form in the current window, so
  # `save_form` can refuse the excess before any mail, upload or row is written -- the endpoint is
  # public and, unless the form carries a captcha field, otherwise unthrottled. A read only: only a
  # *stored* submission spends budget (see `record_submission`), so a flood of submissions that fail
  # validation -- or that never solve a captcha -- cannot exhaust the window and lock out a co-NAT
  # visitor whose own submission is valid.
  def submission_over_limit?(form)
    Rails.cache.read(submission_throttle_key(form), raw: true).to_i >= submission_limit
  end

  # Spend one unit of this IP's per-form budget, called once a row has actually been written so the
  # cap tracks resource-consuming submissions rather than mere attempts.
  #
  # The counter is an ATOMIC Rails.cache increment mirroring camaleon_cms's login throttle. Its helper
  # (cama_captcha_increment_attack) is deliberately not reused: it also mutates session state, which
  # this IP-only throttle must not do on a public, session-light request (and its unit spec drives a
  # bare controller with no session). `raw: true` keeps the value a bare integer so Redis/Memcached
  # INCR is atomic (a harmless no-op on Memory/File stores). Older Memory/File stores (Rails < 7.1)
  # return nil for a missing key instead of seeding it; seed it then, with `unless_exist` so the seed
  # can never overwrite a counter a concurrent request has already advanced.
  #
  # The window is FIXED, not sliding: the TTL is anchored when the key is first written and not
  # refreshed on later increments (ActiveSupport preserves the original `expires_at`, and
  # Redis/Memcached only set a TTL at creation), so the budget resets in full once the window since
  # the first stored submission elapses. The throttle is only as strong as the host's cache: it fails
  # open on a null store, and on a per-process store (Rails' default MemoryStore, or FileStore across
  # hosts) each worker counts on its own, so an effective cap needs a shared store (Redis/Memcached).
  # The key is the client IP as camaleon_cms resolves it (`request.remote_ip`), so it is only as
  # trustworthy as the app's trusted-proxy configuration.
  def record_submission(form)
    key = submission_throttle_key(form)
    counted = Rails.cache.increment(key, 1, expires_in: SUBMISSION_THROTTLE_WINDOW, raw: true)
    return unless counted.nil?

    Rails.cache.write(key, 1, expires_in: SUBMISSION_THROTTLE_WINDOW, unless_exist: true, raw: true)
  end

  def submission_throttle_key(form)
    "cama_contact_form_submit:#{current_site.id}:#{request.remote_ip}:#{form.id}"
  end

  # The per-window budget from `contact_form_max_submits`, as a positive integer.
  def submission_limit
    positive_site_option('contact_form_max_submits', SUBMISSION_THROTTLE_DEFAULT_MAX)
  end

  # The per-submission attachment budget from `contact_form_max_files`, as a positive integer.
  def attachment_limit
    positive_site_option('contact_form_max_files', ATTACHMENT_COUNT_DEFAULT_MAX)
  end

  # A limit option, as a positive integer. get_option hands back whatever was stored, and
  # camaleon_cms's set_option runs values through String#to_var -- so a "true"/"false" option is a
  # boolean (and `false.to_i` raises), a cleared one is nil, and a stray "unlimited"/0 would coerce
  # to 0 and refuse every submission (or every attachment) site-wide. Anything that is not a
  # positive integer falls back to the default rather than 500-ing or silently bricking the form; to
  # loosen a limit an operator sets a higher positive integer.
  #
  # A String is parsed in base 10 explicitly: to_var stores only canonical numerals as numbers, so
  # a typed "010" survives as a String, and bare Integer() would read its leading zero as octal --
  # a silently wrong limit. Base 10 reads it as ten, and rejects "0x10" into the fallback.
  def positive_site_option(name, default)
    value = current_site.get_option(name, default)
    parsed = value.is_a?(String) ? Integer(value, 10, exception: false) : Integer(value, exception: false)
    parsed&.positive? ? parsed : default
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
    # One refusal, outright and first, for every shape no real form produces -- a missing form, a
    # non-hash fields, a forged file-field value. Each is a forged request, not a validation error
    # the visitor can act on; nothing is stored either way, so there is nothing to gain by
    # continuing -- and continuing means running the rest of this method over input already known
    # to be hostile, including a reCAPTCHA round-trip to an external service. Rejecting the file
    # shapes is also what keeps forged entries away from the uploader (see
    # malformed_file_submission?, whose walk the earlier disjuncts' short-circuit vouches for).
    #
    # The message names no field and quotes nothing back. The frontend flash partial renders with
    # `raw`, so echoing the refused value there would make the refusal itself an injection sink --
    # the same trap as the admin path.
    if form.blank? || !(fields.is_a?(Hash) || fields.is_a?(ActionController::Parameters)) ||
       malformed_file_submission?(form, fields)
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

    # perform_save_form's file loop uploads and persists every entry submitted under a file field,
    # so the entry count is budget the visitor spends -- bounded here, before any upload runs,
    # rather than left to multiply against the per-file size cap. Over the cap the submission is
    # refused whole, with the other validation errors: trimming to the first N would silently drop
    # files the visitor believes they sent, and the file input is `multiple` with no client-side
    # cap, so a legitimate visitor can hit this and needs the actionable message.
    if attachment_count(form, fields) > (max_files = attachment_limit)
      # The %{max} substitution runs on the resolved message so an author-customized
      # `invalid_files_count` can carry the limit too -- `the_message` returns a custom message
      # verbatim, while the i18n default has already interpolated and is left untouched.
      errors << form.the_message('invalid_files_count',
                                 t('.too_many_files_val',
                                   max: max_files,
                                   default: 'Too many files attached (maximum %{max}). ' \
                                            'Please remove some files and try again.'))
                    .to_s.gsub('%{max}', max_files.to_s)
      validate = false
    end

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

  # Whether any file field carries a value no real form submission produces. The renderer encodes a
  # file field as `fields[cid][]` file parts, and Rack drops an empty-filename part, so the only
  # legitimate shapes are an absent value -- nil, literally, which is why the skip below tests
  # exactly that and not `blank?`: a blank-but-present value (`fields[cid]=`, a JSON `false`) is as
  # forged as any other scalar, and the upload loop's `.to_a` raises on it all the same -- and an
  # array of uploaded files. A bare string, a nested hash, a non-file entry -- each previously
  # raised in the upload loop (`String#to_a`, `original_filename`), an unauthenticated 500.
  #
  # Refusing the whole submission, rather than skipping the forged entries, is load-bearing: a
  # String that survived to cama_tmp_upload would be treated there as a URL to download or a local
  # path to copy, and an anonymous visitor must never steer that.
  def malformed_file_submission?(form, fields)
    form.fields.any? do |f|
      next false unless f[:field_type] == 'file'

      value = fields[f[:cid].to_sym]
      next false if value.nil?

      !value.is_a?(Array) || !value.all?(ActionDispatch::Http::UploadedFile)
    end
  end

  # The number of entries perform_save_form's upload loop would iterate for this submission:
  # everything submitted under a file field. The shape gate has already refused anything that is
  # not an absent value or an array of uploaded files, so this is those arrays' sizes summed --
  # `Array()` keeps the sum total without a shape judgment of its own, the same counting
  # convert_form_values uses.
  def attachment_count(form, fields)
    form.fields.sum do |f|
      f[:field_type] == 'file' ? Array(fields[f[:cid].to_sym]).size : 0
    end
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
