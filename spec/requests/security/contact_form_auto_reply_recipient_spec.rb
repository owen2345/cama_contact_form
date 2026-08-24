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

  def submit(c1_value)
    post '/plugins/cama_contact_form/save_form', params: { id: form.id, fields: { c1: c1_value } }
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
  end
end
