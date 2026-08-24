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

  # Every recipient handed to the mailer, in call order. Spying on the seam `cama_send_email` calls
  # (`CamaleonCms::HtmlMailer.sender(recipient, subject, args)`) keeps the assertion independent of the
  # queue adapter -- the dummy app loads no ActiveJob, so `deliver_later` reaches no `deliveries` array.
  let(:sent_to) { [] }

  before do
    form
    site.the_post('sample-post').update!(content: "[forms slug='contact']")
    allow(CamaleonCms::HtmlMailer).to receive(:sender) do |recipient, *_|
      sent_to << recipient
      instance_double(ActionMailer::MessageDelivery, deliver_later: nil)
    end
  end

  def submit(c1_value, to: form)
    post '/plugins/cama_contact_form/save_form', params: { id: to.id, fields: { c1: c1_value } }
  end

  # The owner notification fires first (author-configured recipient), the auto-reply second. So a
  # submission whose auto-reply is refused leaves exactly the owner address behind.
  describe 'a reply-address field carrying an injected recipient' do
    it 'does not send the auto-reply to a CRLF header-injected address' do
      submit("victim@example.com\r\nBcc: everyone@example.com")

      expect(sent_to).to eq(['owner@example.com'])
    end

    it 'does not send the auto-reply to a comma-separated recipient list' do
      submit('a@evil.com, b@evil.com, c@evil.com')

      expect(sent_to).to eq(['owner@example.com'])
    end

    it 'does not send the auto-reply to a space-separated pair either' do
      submit('victim@example.com attacker@evil.com')

      expect(sent_to).to eq(['owner@example.com'])
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
end
