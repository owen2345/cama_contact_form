# Change Log

## Unreleased

### Security: submissions cap their attachment count, and forged file values are refused

One public POST could attach unbounded many files, all persisted under `public/contact_form` and mailed. A submission is now refused whole past `contact_form_max_files` total files (default 5), before any upload, row or mail; the message is customizable as `invalid_files_count`. A file-field value no real form produces (anything but an array of uploaded files) is refused as invalid instead of raising a 500. [#81](https://github.com/owen2345/cama_contact_form/pull/81).

### Tooling: Ruby 3.4.10 and RubyGems/Bundler 4.0.19

Bumps the development toolchain to Ruby 3.4.10 (`.tool-versions`) and RubyGems/Bundler 4.0.19 across CI and the release workflow (RuboCop 1.90). The gemspec's `required_ruby_version` stays `>= 3.0`, so the packaged gem is unchanged. Development/CI only. [#80](https://github.com/owen2345/cama_contact_form/pull/80).

### Security: contact-form submissions are rate-limited per IP

The public `save_form` is now capped per client IP per form: past `contact_form_max_submits` stored submissions (default 10) in a fixed 15-minute window, the excess is refused before any mail, upload or row. Only stored submissions count; a real cap needs a shared cache store. Requires `camaleon_cms >= 2.9.4`, checked at boot. Also stops a stored response being resubmitted as a form, and same-second responses colliding. [#77](https://github.com/owen2345/cama_contact_form/pull/77).

## 0.1.13

### Security: the contact-form auto-reply validates its recipient (CF-1)

The optional confirmation e-mail went to whatever address the visitor typed into the field named by the `to_answer` setting — an unauthenticated, fully attacker-controlled recipient — which turned the site into an email cannon firing from its own From address. The recipient is now stripped of surrounding whitespace and must be a single well-formed address (`URI::MailTo::EMAIL_REGEXP`), so one submission can neither header-inject a Bcc nor fan out to a recipient list; a refused auto-reply is logged. Email-type fields are validated with the same rule at submission time, so a malformed address is a visible error rather than a confirmation that silently never arrives. The owner notification is unaffected. [#76](https://github.com/owen2345/cama_contact_form/pull/76).

### Security: authored-markup gate delegates to camaleon-cms's UnsafeMarkup

The admin form editor's markup gate now calls `CamaleonCms::UnsafeMarkup` instead of a drifted private fork. This closes a gap the core detector already covered: entity-encoded markup smuggled through a kept attribute (`title`, `data-*`, `aria-*`) and injected as live markup by a `data-html` sink (Bootstrap tooltip/popover) was accepted, now refused. Requires `camaleon_cms >= 2.9.3`, now checked at load with a clear error. [#75](https://github.com/owen2345/cama_contact_form/pull/75).

### Tooling: stricter RuboCop cops

Enables RuboCop cops the initial setup had relaxed, fixing the code rather than exempting it: frozen-string comments, class/module docs, `Rails/TimeZone` (UTC timestamps), an `ob`→`obj` rename, and `NewCops`. Development dependencies move to the Gemfile. `Rails/InverseOf` and `Gemspec/RequireMFA` stay exempt, with reasons. Development/CI only; the packaged gem is unchanged. [#74](https://github.com/owen2345/cama_contact_form/pull/74).

### Testing: the contact-form specs now live with the plugin

Moves the contact-form request specs and the `:js` admin feature spec into this repo, which now has its own camaleon_cms-backed harness (headless Chrome for the feature spec). The `contact_form_unfiltered_html` permission-model spec stays in camaleon-cms. Development/CI only. [#73](https://github.com/owen2345/cama_contact_form/pull/73) · pairs with [camaleon-cms#1278](https://github.com/owen2345/camaleon-cms/pull/1278).

### Tooling: RuboCop, a committed lockfile, and CI caching

Adds RuboCop (same plugin set and config as camaleon_cms) and brings the code up to it, a few size/complexity cops relaxed for documented reasons. Commits `Gemfile.lock` so gem versions are reproducible and CI's `bundler-cache` works; adds a RuboCop result cache. Development/CI only. [#72](https://github.com/owen2345/cama_contact_form/pull/72).

### Testing: the plugin now has its own RSpec suite

Adds a camaleon_cms-backed dummy Rails app under `spec/` so the plugin can be tested in its own repo. Floors the `camaleon_cms` dev dependency at `>= 2.9.3` (a core with the upload scanner and save-time gate), closing audit finding CF-8. Development/CI only. [#71](https://github.com/owen2345/cama_contact_form/pull/71).

### Security: the `forms` shortcode is gated by camaleon-cms

Declares the plugin's `forms` shortcode to camaleon-cms's boot-time `ShortcodeRegistry`, so a non-admin without the new `content_shortcodes` permission can no longer save `[forms ...]`. Guarded against cores predating the registry; rendering is unchanged. [#69](https://github.com/owen2345/cama_contact_form/pull/69) · pairs with [camaleon-cms#1277](https://github.com/owen2345/camaleon-cms/pull/1277).

## 0.1.12

Two independent changes ship together. Each section links its PR — the reasoning, the exploits and
the measurements are there, not here.

### Security: form content is refused, not rewritten

[#65](https://github.com/owen2345/cama_contact_form/pull/65) · pairs with
[camaleon-cms#1215](https://github.com/owen2345/camaleon-cms/pull/1215), which supplies the
`contact_form_unfiltered_html` permission and hosts this plugin's test suite. Reported by Amir Aliu
and Enrik Mustafa. **Supersedes 0.1.10 and 0.1.11**, which both rewrote the author's input; neither
reached RubyGems.

A form's content is stored and delivered exactly as written, or the save is refused and the author is
told which setting to fix. Nothing the plugin stores or renders into a form is escaped or sanitized.
Escaping is not idempotent — a re-saved value grows another layer of entity references every pass —
and sanitizing discards the author's work without saying so. Refusing avoids both, and buys the
property that makes verbatim rendering safe: stored content always equals authored content.

- **Every gated position is checked against the context it actually renders in**, and the context is
  now fixed rather than inferred — a `template` may no longer place a placeholder inside a tag, so it
  cannot relocate a value into an attribute the gate is not judging it against.
- **The markup test is structural as well as differential**: a value may not leave a tag open, and
  every tag it writes must survive parsing. The sanitizer comparison alone was blind to both.
- **Also refused:** an event-handler attribute name, an entity-encoded script URL
  (`formaction="javascript&colon;…"`), `rel="opener"`, and a visitor's value carrying active markup
  into the notification e-mail, which renders with `raw`.
- **Fixed for everyone:** checkbox, radio and file submissions were all being refused; six crashes
  reachable from an ordinary request, one an unauthenticated 500; ordinary prose was refused
  (`Tom & Jerry`, a translated `5 < 10`, `-->`, `data-*`/`aria-*`/`role`); and the gate's cost was
  chosen by the caller — 4093 option labels measured 17 s of CPU in a single request.

**Breaking changes**

- A save that previously succeeded may now be refused. The message names the setting, never the
  content it refused.
- **Some refusals bind every author, administrators included**, because they describe records the
  renderer cannot read rather than content a role may not write: a placeholder inside a tag in a
  `template`; a radio, checkbox or dropdown field with no options; a non-scalar `required`;
  `field_attributes` that is valid JSON but not an object; and caps of 200 fields, 100 options per
  field, and 64 KB per gated value. Each of these previously saved successfully and then raised on
  every visit to the public page.
- `rel` and `target` are no longer accepted in authored markup.
- Radio and checkbox `value=` is restored to the 0.1.8 wire format — the plain lowercased label. An
  earlier refactor had switched it to the underscore form used by dropdowns, which no existing
  response row would match.
- **Requires** the Camaleon CMS release supplying `contact_form_unfiltered_html` (on `master` after
  2.9.2). On an older version the plugin still refuses unsafe content, but only administrators are
  trusted.

### Packaging

[#66](https://github.com/owen2345/cama_contact_form/pull/66) ·
[#67](https://github.com/owen2345/cama_contact_form/pull/67)

- **The gem no longer ships its own test suite.** `s.test_files` was set to `Dir["test/**/*"]`, and
  RubyGems merges `test_files` into `files`, so the whole `test/` tree was published despite
  `s.files` listing only `{app,config,db,lib}`. The package drops from 62 files to 26.
- **The README is now included.** `s.files` referenced `README.rdoc`, which does not exist here, so
  every release so far shipped without one. The same stale name is fixed in the `Rakefile` rdoc task.
- **`required_ruby_version` is declared as `>= 3.0`**, matching camaleon_cms, so Bundler stops
  offering this gem to projects on an older Ruby.
- **A homepage is set**, so the RubyGems page links back to this repository.

Releases are also cut differently: the reusable action that derived the version from the newest git
tag is replaced by a manually started workflow that treats `lib/cama_contact_form/version.rb` as the
single source of truth, and publishes to RubyGems. See *Releasing* in the README. This does not
affect the released gem.

## 0.1.11

Narrows the escaping introduced in 0.1.10, which was over-broad. **Supersedes 0.1.10 — upgrade
straight to this version.**

0.1.10 escaped every form-definition value, including field labels, descriptions and option labels.
That closed the vulnerability but broke a legitimate capability: an administrator could no longer put
so much as a `<strong>` or a link in a field label. The permission was called "Allow unfiltered HTML
in contact forms" while covering only three of the nine positions a form renders.

Escaping is now decided by **HTML context** rather than applied uniformly:

- **Element content renders as markup** — field labels, descriptions, radio/checkbox option labels
  and the submit button label, alongside the form wrappers and field templates that already did.
  These are sanitized when the form is saved unless the author holds
  `contact_form_unfiltered_html`, so a trusted author's formatting survives and an untrusted
  author's script does not.
- **Attribute values stay escaped unconditionally** — `field_options[:field_class]`,
  `default_value`, and the `value` attribute derived from an option label. Sanitizing cannot protect
  this context: `form-control" onfocus="alert(1)` contains no tags, so an HTML sanitizer returns it
  unchanged and rendering it raw would inject a live event handler. There is no markup use case for
  a CSS class or a prefilled input value.
- **A visitor's own submitted values remain escaped in every position**, with no permission able to
  exempt them. Unauthenticated input never passes through the save-time sanitizer.

**Not covered:** markup in a *dropdown* option label still will not render. `<option>` is text-only
per the HTML specification, so a browser discards any element inside it regardless of what the server
emits. Radio and checkbox option labels render inside a `<label>` and are unaffected.

> **Correction, added in 0.1.12:** the paragraph above is wrong, and was wrong when it was written.
> `<option>` is not text-only — `<script>` inside one survives parsing and executes, and `<template>`
> survives as well; only ordinary formatting elements are dropped. Nothing about a dropdown option
> label may be relied on as inert, so 0.1.12 gates that position like every other
> ([#65](https://github.com/owen2345/cama_contact_form/pull/65)). Formatting markup in a dropdown
> option label still will not render, but that is a display limitation, not a security boundary.

**Behavior change from 0.1.10:** field labels, descriptions, option labels and the submit button
label render as markup again. If you upgraded to 0.1.10 and saw markup in those fields turn into
visible text, this restores it — but only for values saved by a trusted author, since existing values
are re-sanitized the next time the form is saved.

## 0.1.10

Reported by Amir Aliu and Enrik Mustafa. [#63](https://github.com/owen2345/cama_contact_form/pull/63)

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
