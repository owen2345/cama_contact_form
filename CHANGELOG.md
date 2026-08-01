# Change Log

## 0.1.12

Replaces the escaping in 0.1.10 and 0.1.11 with refusal. **Supersedes both — upgrade straight to
this version.** Neither of them reached RubyGems.

Reported by Amir Aliu and Enrik Mustafa.
[camaleon-cms#1215](https://github.com/owen2345/camaleon-cms/pull/1215)

**Nothing is rewritten any more.** A form's content is stored and delivered exactly as written, or
the save is refused and the author is told which field to fix. No value the plugin stores or renders
into a form is escaped or sanitized: an HTML sanitizer is consulted only as an oracle at save time,
and its output is compared and discarded, never persisted. (The notification e-mail's field-summary
table still escapes, as ordinary ERB — it is a data table, not authored markup.)

Both earlier attempts rewrote the author's input, and both were wrong in the same way. Escaping is
not idempotent: a value re-saved through the form editor grows another layer of entity references on
every pass. Sanitizing silently drops the author's work, with no indication of what went missing.
Both leave the editor showing something other than what was typed. Refusing avoids all of that, and
buys the property that makes verbatim rendering safe — stored content always equals authored
content, so the renderer introduces nothing the writer did not put there.

- **Security fix:** `Plugins::CamaContactForm::AdminFormsController#update` refuses a save carrying
  content the author's role is not permitted to write, before it touches the record. The gated
  positions are the form wrappers (`previous_html`, `after_html`), the notification e-mail's `body`,
  `body_answer`, `subject` and `subject_answer`, the submit button label, every response message,
  each field's `label`, `description`, `template`, `field_class`, `default_value` and
  `field_attributes`, each option label, and the reCAPTCHA site key. An author holding
  `contact_form_unfiltered_html` is subject to none of it.

  **The position each value renders in is fixed rather than inferred.** A field `template` that puts
  `[ci]`, `[label ci]` or `[descr ci]` inside a tag is refused, for **everyone** — including a grant
  holder. Without that rule the template decides the HTML context of a value written somewhere else,
  possibly by someone else: `<div class='[descr ci]'>` put a description inside a single-quoted
  attribute, where an apostrophe escaped and no rule was looking for one, and `<div title="[ci]">`
  put a whole `<textarea>` element inside an attribute, where the RCDATA rule described nothing. With
  the position fixed, a description is element content and a double quote in one is ordinary prose
  again.

  The test applied is the narrowest one per position: an element-content value is refused when an
  HTML sanitizer would change it; a value landing inside a double-quoted attribute is refused only
  for containing `"`; a value redisplayed as `<textarea>` content is refused only for containing
  `</textarea`, since a quote is ordinary prose there. A value that can reach more than one of those
  contexts must satisfy each — an option label is element content inside its `<label>` *and* the
  source of the control's `value="…"`, so it carries both rules.

- **Security fix:** the markup test is structural as well as differential. Comparing the sanitizer's
  output against the reserialized input only sees what the safe list *removed*, and is blind to
  anything the parser discards first:

  - a tag whose attribute list never closes is dropped at EOF by both sides and compares equal, but
    the browser is not at EOF — `<div class="a" onmouseover="alert(1)" x="` finishes its attribute at
    the next quote in the document and lands a live handler on the page;
  - a tag the parser cannot place is foster-parented away before the sanitizer ever sees it —
    `<td onmouseover="alert(1)">x</td>` parses to bare text on its own, then renders as a live cell
    as soon as anything opens table context around it.

  Both are refused now: a value may not leave a tag open, and every tag it writes must survive the
  parse.

- **Security fix:** `field_attributes` refuses an attribute *name* denoting an event handler, not
  merely a malformed one. `onfocus` is a well-formed attribute name carrying a quote-free value, so
  it escapes nothing — it simply is script. A URL-bearing attribute is decoded **by the HTML parser**
  before its scheme is checked: `CGI.unescapeHTML` knows the five legacy entities and numeric
  references and nothing else, so `formaction="javascript&colon;alert(1)"` walked straight past it
  while a browser resolves it to `javascript:`.

- **Security fix:** structural values are allowlisted for **every** author, including one holding the
  grant: `cid` must be a plain identifier, `field_type` one of the known types, `maxlength` numeric,
  `required` a scalar, a choice field's option list non-empty, and `field_attributes` a JSON *object*
  rather than merely valid JSON. A field typed `text" onfocus="x` is a corrupt record, not a
  capability — and every one of the others was a permanent 500 on every public page, reported to the
  author as a successful save.

- **Security fix:** a visitor's submission is refused rather than escaped, and refused whole.
  `validate_to_save_form` returns immediately, before reCAPTCHA and before the e-mail format check —
  nothing is stored either way, and continuing means a round trip to an external service on input
  already known to be hostile. `FrontController#save_form` then stashes nothing into `flash[:values]`:
  redisplay is the only reason a submission reaches the page at all, so a submission carrying a
  payload in any field is echoed back in none of them.

  A submitted value is judged **as the renderer will interpolate it** — `values[cid]` goes straight
  into the markup, so a non-String is judged by its `to_s`. That is how an Array or a Hash used to
  supply the double quote that closed the attribute without the payload needing one of its own. It is
  applied only to the field types that are actually echoed back (`text`, `website`, `email`,
  `paragraph`, `textarea`); judging `Array#to_s` for every type instead refused **every** checkbox,
  radio and file submission, because `Array#to_s` is `inspect` and always carries quotes.

- **Security fix:** the notification e-mail is treated as the markup sink it is. `cama_replace_codes`
  splices every submitted value into the author's `body`/`body_answer`, and the mailer renders both —
  and the subject — with `raw`. A submitted value carrying a script element, an event handler or a
  script URL is refused; ordinary prose is not, so `Fish & Chips <today>` still round-trips. The
  author's own `subject` and `subject_answer` are gated as markup for the same reason.

- **Fix:** the three placeholders are substituted in **one pass**. Substituting `[ci]`, then
  `[descr ci]`, then `[label ci]` meant each pass scanned the output of the one before it, so a
  visitor typing the literal `[label ci]` into a message had the author's label spliced into the
  middle of the textarea echoing their own words back.

- **Security fix:** a refusal message never repeats what it refused. Both the admin and the frontend
  flash partials render with `raw`, so an earlier revision that interpolated the author's own field
  label into the error made refusing an injection a way to perform one. The admin message names only
  this controller's own fixed constants; the visitor-facing message names no field at all.

- **Fix:** the cost of the gate is no longer chosen by the caller. Each gated value costs a full
  HTML parse, and both the number of values and their size arrived unbounded from `params`:

  - `railscf_message` is permitted against a known key list — roughly 4090 keys fit inside Rack's
    parameter cap and pinned a worker for over half a second;
  - a field's option list is capped at 100 and the field list at 200 — 4093 option labels measured
    8,186 parses and **17 seconds** of CPU in one request;
  - a single gated value is capped at 64 KB — one 1 MB `template` measured 20 seconds, and the admin
    editor posts multipart, so Rack's 4 MB urlencoded ceiling did not apply.

  Every one of these was reachable by an account holding nothing but `:manage, :plugins`. Values are
  also walked lazily now, a value containing no character the parser treats specially skips the parse
  altogether, and each check parses once rather than twice.

- **Fix:** a rejected save no longer discards the author's work. The editor is repopulated from the
  submitted params rather than redrawn from the stored record, so an author who is told which setting
  to fix still has the rest of their edit in front of them. (Malformed fields are dropped from the
  redraw — the message already names what was wrong with them.)

- **Fix:** several crashes reachable from an ordinary request:

  - `POST save_form` with an id naming no form no longer raises — an unauthenticated 500;
  - `fields=` (an empty string) no longer reaches `String#each`;
  - a settings container that is a scalar is refused rather than stored and then dereferenced;
  - a form saved without its settings containers renders instead of raising, via the model's new
    `mail_settings` / `form_button_settings` / `message_settings` readers;
  - an e-mail field the submitter simply omits no longer reaches `nil.match`;
  - a stored `required` of anything other than a boolean string no longer reaches `String#to_bool`,
    which raises on values it does not recognize.

- **Fix:** the refusal message names the rule that actually fired. An author who typed `btn "primary"`
  into Custom Class was told the value "contains HTML", sending them after markup that is not there
  and pointing them at a permission that would not have applied; `field_attributes` refused for an
  event-handler name was told to remove a double quote it did not contain.

**Requires the Camaleon CMS release that supplies the `contact_form_unfiltered_html` permission.**
That permission is on `master` after 2.9.2 and unreleased at the time of writing — expected as
2.9.3. On an older Camaleon the plugin still runs and still refuses unsafe content, but the grant has
no checkbox in the role editor, so in practice only administrators are trusted — they hold
`can :manage, :all` regardless — and no other role can be given the exemption without editing role
meta by hand.

**Behavior change:** a save that previously succeeded may now be refused. An author without the grant
who has HTML in a field label, description or template is told *which setting* to fix — the message
names the setting, such as `template` or `option label`, and deliberately never quotes back the
content it refused. Existing stored content is not re-checked and keeps rendering until the form is
saved again.

**Behavior change:** some refusals bind **every** author, administrators and grant holders included,
because they describe records the renderer cannot read rather than content a role may not write. A
save is refused for anyone when a `template` puts `[ci]`, `[label ci]` or `[descr ci]` inside a tag;
when a radio, checkbox or dropdown field carries no options; when `required` is not a scalar; when
`field_attributes` is valid JSON but not an object; or when a form exceeds 200 fields, a field
exceeds 100 options, or a single gated value exceeds 64 KB. Every one of these previously saved
successfully and then raised on every visit to the public page.

**Behavior change:** ordinary punctuation and formatting are accepted. A visitor may write a quote in
a message, and `Fish & Chips <today>` round-trips as written for them. Authors keep `Tom & Jerry`,
`&nbsp;`, `&copy;`, `<br/>`, uppercase tags, single-quoted attributes and the plugin's own default
field template — all of which an earlier revision of this gate refused, because it compared the
sanitizer's output against the input and so tested spelling rather than safety. Also accepted, and
also refused by an earlier revision: `data-*`, `aria-*`, `role` and `tabindex` in a template (a
Bootstrap wrapper and an accessible field template are most of what `template` exists for); a
translated value containing a comparison, such as `<!--:en-->Only 5 < 10 left<!--:-->`; prose
containing an ASCII arrow, such as `Step 1 --> Step 2`; and a double quote in a description, which
can now only ever be element content. A `"` in a **label** or an **option label** is still refused for
an untrusted author, because the renderer itself puts both into an attribute.

**Behavior change:** `rel` and `target` are no longer accepted in authored markup. Rails omits them
from its safe list deliberately: `rel="opener"` is the explicit opt-back-in to the `window.opener`
handle browsers disable for `target="_blank"`, and it lets an untrusted author repoint the visitor's
original tab at a look-alike login page. An author who needs them can be granted the permission.

**Not covered:** *formatting* markup in a dropdown option label still will not render — a browser
drops `<b>` and its neighbours inside `<option>`. This is not a guarantee that an `<option>` is inert:
`<script>` inside one survives parsing and executes, and `<template>` survives too, so the position is
gated on the same terms as every other. Radio and checkbox option labels render inside a `<label>` and
are unaffected.

### Packaging

Shipped in the same release, unrelated to the security work above.
[#66](https://github.com/owen2345/cama_contact_form/pull/66)

- **The gem no longer ships its own test suite.** `s.test_files` was set to `Dir["test/**/*"]`, and
  RubyGems merges `test_files` into `files`, so the whole `test/` tree was published despite
  `s.files` listing only `{app,config,db,lib}`. The package drops from 62 files to 26.
- **The README is now included.** `s.files` referenced `README.rdoc`, a file that does not exist in
  this repository — `Dir[]` matched nothing and said nothing, so every release so far shipped
  without a README. The same stale name is fixed in the `Rakefile` rdoc task.
- **`required_ruby_version` is now declared as `>= 3.0`**, matching camaleon_cms. Bundler will stop
  offering new versions of this gem to projects on an older Ruby, rather than installing a gem that
  cannot run.
- **A homepage is set**, so the gem page on RubyGems links back to this repository.

Releases are also cut differently now: the reusable action that derived the version from the newest
git tag is replaced by a manually started workflow that treats `lib/cama_contact_form/version.rb`
as the single source of truth, and publishes to RubyGems. See *Releasing* in the README. This does
not affect the released gem.

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
> label may be relied on as inert. See the 0.1.12 entry.

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
