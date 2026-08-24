# frozen_string_literal: true

# CF-1 (SECURITY-AUDIT-2026-08-11): the contact form's optional auto-reply ("confirmation e-mail")
# sends to whatever address the visitor typed into the field named by `to_answer` -- an
# unauthenticated, fully attacker-controlled recipient. Unchecked, it turns the site into an email
# cannon firing from the site's own From address and reputation. The recipient is now validated to a
# single well-formed address before the auto-reply is sent, so one submission can neither header-inject
# (a Bcc to thousands) nor fan out to a recipient list. The owner notification -- an author-configured
# recipient -- is unaffected, and per-submission volume is out of scope here (CF-2, rate limiting).
RSpec.describe 'Security: contact form auto-reply recipient' do
  let!(:site) { CamaleonCms::Site.first.decorate }

  # A form whose auto-reply is configured: `to_answer` points at field c1, so the visitor's own c1
  # value becomes the confirmation recipient.
  let(:form) do
    site.contact_forms.create!(
      name: 'Contact', slug: 'contact',
      value: { fields: [{ label: 'Email', field_type: 'email', cid: 'c1', required: 'true',
                          field_options: {} }] }.to_json,
      settings: {
        'railscf_mail' => { 'to' => 'owner@example.com', 'subject' => 'New', 'body' => 'b',
                            'to_answer' => '[c1]', 'subject_answer' => 'Thanks', 'body_answer' => 'Got it' },
        'railscf_message' => {}, 'railscf_form_button' => { 'name_button' => 'Send' }
      }.to_json
    )
  end

  # A second form whose reply field is a plain text field: no browser-side email cleanup applies and
  # the server's email-field validation does not run, so submissions here exercise the send-time
  # guard alone.
  let(:text_form) do
    site.contact_forms.create!(
      name: 'Contact text', slug: 'contact-text',
      value: { fields: [{ label: 'Reply to', field_type: 'text', cid: 'c1', required: 'true',
                          field_options: {} }] }.to_json,
      settings: {
        'railscf_mail' => { 'to' => 'owner@example.com', 'subject' => 'New', 'body' => 'b',
                            'to_answer' => '[c1]', 'subject_answer' => 'Thanks', 'body_answer' => 'Got it' },
        'railscf_message' => {}, 'railscf_form_button' => { 'name_button' => 'Send' }
      }.to_json
    )
  end

  # A third form whose reply field is a checkboxes field: its value arrives as an Array, and unlike
  # on echoed field types -- where the markup gate refuses any Array first because `Array#to_s`
  # always carries quotes -- it sails through to the send-time guard.
  let(:checkboxes_form) do
    site.contact_forms.create!(
      name: 'Contact boxes', slug: 'contact-boxes',
      value: { fields: [{ label: 'Pick', field_type: 'checkboxes', cid: 'c1', required: 'false',
                          field_options: { options: [{ label: 'a@b.com', checked: false }] } }] }.to_json,
      settings: {
        'railscf_mail' => { 'to' => 'owner@example.com', 'subject' => 'New', 'body' => 'b',
                            'to_answer' => '[c1]', 'subject_answer' => 'Thanks', 'body_answer' => 'Got it' },
        'railscf_message' => {}, 'railscf_form_button' => { 'name_button' => 'Send' }
      }.to_json
    )
  end

  # Every recipient handed to the mailer, in call order. Spying on the seam `cama_send_email` calls
  # (`CamaleonCms::HtmlMailer.sender(recipient, subject, args)`) keeps the assertion independent of the
  # queue adapter -- the dummy app loads no ActiveJob, so `deliver_later` reaches no `deliveries` array.
  let(:sent_to) { [] }

  # No page is published or rendered here: save_form looks the form up purely by params[:id]
  # (front_controller.rb) and every example only POSTs, so the shortcode-on-a-post setup the
  # page-rendering siblings need has no place in this file.
  before do
    form
    allow(CamaleonCms::HtmlMailer).to receive(:sender) do |recipient, *_|
      sent_to << recipient
      instance_double(ActionMailer::MessageDelivery, deliver_later: nil)
    end
  end

  def submit(c1_value, to: form)
    post '/plugins/cama_contact_form/save_form', params: { id: to.id, fields: { c1: c1_value } }
  end

  # The owner notification fires first (author-configured recipient), the auto-reply second. So a
  # submission whose auto-reply is refused leaves exactly the owner address behind. These target the
  # text-field form: on the email-field form the same shapes are stopped earlier, by field
  # validation (next group), and the send-time guard must hold on its own for every other field
  # type `to_answer` can name.
  describe 'a reply-address field carrying an injected recipient' do
    it 'does not send the auto-reply to a CRLF header-injected address' do
      submit("victim@example.com\r\nBcc: everyone@example.com", to: text_form)

      expect(sent_to).to eq(['owner@example.com'])
    end

    it 'does not send the auto-reply to a comma-separated recipient list' do
      submit('a@evil.com, b@evil.com, c@evil.com', to: text_form)

      expect(sent_to).to eq(['owner@example.com'])
    end

    it 'does not send the auto-reply to a space-separated pair either' do
      submit('victim@example.com attacker@evil.com', to: text_form)

      expect(sent_to).to eq(['owner@example.com'])
    end

    # Without the log line the response is indistinguishable from full success, and "customers say
    # the confirmation never arrives" is undiagnosable. The value itself must stay out of the log:
    # it is hostile by hypothesis.
    it 'logs the refusal, naming the form but never the refused value' do
      logged = []
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }

      submit('victim@example.com attacker@evil.com', to: text_form)

      expect(logged.join).to include("form #{text_form.id}", 'CF-1')
      expect(logged.join).not_to include('attacker@evil.com')
    end
  end

  # The email-type field is validated with the same rule the send-time guard applies
  # (`normalized_email_address`), so a value the guard would refuse becomes an actionable error at
  # submission time -- not a success message followed by a confirmation that never arrives. The
  # validation failure precedes both mails, so nothing is sent at all.
  describe 'an email field carrying a value the reply guard would refuse' do
    it 'rejects the submission with a visible error instead of silently withholding the reply' do
      submit('John Doe <john@example.com>')

      expect(sent_to).to eq([])
      expect(flash[:contact_form][:error]).to include('appears invalid')
    end

    it 'rejects an injected recipient list at validation time' do
      submit('a@evil.com, b@evil.com')

      expect(sent_to).to eq([])
    end
  end

  # The feature itself must keep working: a real submitter address still receives the confirmation.
  describe 'a legitimate submission' do
    it 'still sends the auto-reply to a single well-formed address' do
      submit('real.person@submitter.example')

      expect(sent_to).to eq(['owner@example.com', 'real.person@submitter.example'])
    end

    # A pasted or mobile-typed address often carries a stray surrounding space, and the mailer
    # delivered those before the guard existed -- so the guard strips before judging, and the mail
    # goes to the stripped address, not the padded original.
    it 'sends the auto-reply to the stripped form of a whitespace-padded address' do
      submit(' real.person@submitter.example ')

      expect(sent_to).to eq(['owner@example.com', 'real.person@submitter.example'])
    end

    it 'logs no refusal when the reply is sent' do
      logged = []
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }

      submit('real.person@submitter.example')

      expect(logged.join).not_to include('CF-1')
    end
  end

  # Shapes the Mail gem happily parsed to a working destination before the guard existed, refused now
  # on purpose: name-addr grammar is address-list grammar, and the ASCII-only regexp is what rules
  # out separator smuggling. Pinned here so the narrowing stays a decision, not an accident. The
  # text-field form isolates the send-time guard from the email-field validation.
  describe 'formerly-deliverable shapes the guard deliberately refuses' do
    it 'does not send to a name-addr form (`Jane <jane@example.com>`)' do
      submit('Jane <jane@example.com>', to: text_form)

      expect(sent_to).to eq(['owner@example.com'])
    end

    it 'does not send to a raw-unicode address' do
      submit('user@münchen.de', to: text_form)

      expect(sent_to).to eq(['owner@example.com'])
    end

    it 'does send to the punycode form of the same address' do
      submit('user@xn--mnchen-3ya.de', to: text_form)

      expect(sent_to).to eq(['owner@example.com', 'user@xn--mnchen-3ya.de'])
    end
  end

  # The normalizer promises a non-String value is "rejected through to_s rather than raising".
  # Pinned end-to-end in the one configuration where an Array genuinely reaches the guard, so a
  # cleanup that drops the "redundant" to_s turns this example into a NoMethodError -> 500 on an
  # unauthenticated endpoint instead of staying green.
  describe 'a checkboxes field named by to_answer' do
    it 'refuses the array-shaped recipient without raising' do
      submit(['a@b.com'], to: checkboxes_form)

      expect(response).to have_http_status(:redirect)
      expect(sent_to).to eq(['owner@example.com'])
    end
  end

  # The totality contract, pinned directly: any shape a submitter can force into params comes back
  # nil, never an exception.
  describe 'the recipient normalizer itself' do
    let(:validator) { Class.new { include Plugins::CamaContactForm::ContactFormControllerConcern }.new }

    it 'refuses non-String shapes through to_s instead of raising' do
      expect(validator.normalized_email_address(['a@b.com'])).to be_nil
      expect(validator.normalized_email_address({ 'a' => 'a@b.com' })).to be_nil
      expect(validator.normalized_email_address(ActionController::Parameters.new(a: 'a@b.com'))).to be_nil
      expect(validator.normalized_email_address(nil)).to be_nil
    end

    it 'returns the stripped address for a padded valid one' do
      expect(validator.normalized_email_address(" a@b.com \n")).to eq('a@b.com')
    end
  end
end
