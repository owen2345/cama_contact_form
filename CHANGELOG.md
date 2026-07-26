# Change Log

## 0.1.10

- **Security fix:** Escape form output. `cama_form_element_bootstrap_object` and
  `cama_form_select_multiple_bootstrap` built their markup by raw string interpolation with no
  escaping at any position, and `forms_shorcode.html.erb` emitted the result through `raw`. Two trust
  levels reached those sinks:
  - **Unauthenticated visitors.** `FrontController#save_form` stashes the raw submission into
    `flash[:values]` whenever validation fails, and the shortcode interpolates it back into
    `value="…"` and `<textarea>…</textarea>` so the visitor does not lose their input. A submission
    carrying `" autofocus onfocus="alert(1)` broke out of the attribute.
  - **Any role holding `:manage, :plugins`**, which is the only gate on this plugin's admin
    controller and is not necessarily an administrator. Every form-definition field — label, default
    value, option labels, CSS class — was interpolated unescaped into a page rendered on the public
    site. Because Camaleon serves its admin panel from the same origin, script stored this way runs
    with an administrator's session, making it a privilege escalation.

  Every data position is now escaped with `CGI.escapeHTML` (not `ERB::Util.html_escape`, which is a
  no-op on `html_safe` strings).

- **Security fix:** Sanitize markup-by-contract settings when a form is saved. `previous_html`,
  `after_html` and each field's `template` exist to carry site markup and still render unescaped, so
  escaping them would break the feature. They are instead sanitized on save unless the saving user
  holds the new `contact_form_unfiltered_html` permission — administrators by default. The check
  fails closed, sanitizing, when the acting user or site cannot be resolved, so saves from background
  jobs, rake tasks or the console are sanitized regardless of role.

  `field_options[:field_attributes]` is deliberately excluded: it is JSON rather than HTML, and it is
  safe at render time because Camaleon's `Hash#to_attr_format` escapes attribute values and rejects
  keys that are not valid attribute names.

- **Fix:** Substitute the `[ci]`, `[label ci]` and `[descr ci]` placeholders with the block form of
  `String#sub`/`#gsub`. The String form treats backslash sequences in the replacement as
  backreferences, so a label or value containing `\1` or `\\` was silently corrupted.

**Requires Camaleon CMS 2.9.3 or newer**, which supplies the `contact_form_unfiltered_html`
permission and the fixed `Hash#to_attr_format`.

**Behavior change:** HTML typed into a field label, default value, option label or CSS class now
renders as visible text rather than markup. These are plain-text inputs in the form editor, but
nothing enforced it before.

## 0.1.9 and earlier

Not previously tracked in this file. See the GitHub releases.
