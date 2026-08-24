# frozen_string_literal: true

# CF-2 (SECURITY-AUDIT-2026-08-11): `save_form` is public, unauthenticated, and -- unless the form
# happens to carry a captcha field -- unthrottled, so a script can mail-bomb the owner (and the CF-1
# auto-reply), fill `public/contact_form/<site_id>` with uploads, and flood the responses table.
# Submissions are now capped per client IP per form in a rolling window, and the excess is refused
# before any mail, upload or row is written -- a hard cap rather than a captcha challenge, so a form
# that carries no captcha is still protected.
#
# Each `submission` here runs the real throttle bookkeeping inside its own `with_local_cache`, the way
# Rails scopes a request's cache and discards it at the end. That is the property a rolling per-IP
# counter lives or dies by: the atomic count has to survive in the *underlying* store once the
# request-scoped cache is torn down, or a second request would never see the first. Driving the method
# through that lifecycle -- rather than N times in one straight process, or with the verdict stubbed --
# is what makes these assertions mean something.
RSpec.describe 'Security: contact form submission throttle' do
  let(:store) { ActiveSupport::Cache::MemoryStore.new }
  let(:controller) { Plugins::CamaContactForm::FrontController.new }
  let(:form) { build_form(fields: [text_field(field_type: 'email', label: 'Email')]) }
  let(:ip) { '198.51.100.7' }

  before do
    site.set_option('contact_form_max_submits', 3)
    allow(Rails).to receive(:cache).and_return(store)
    allow(controller).to receive_messages(current_site: site, request: request_from(ip))
  end

  def request_from(addr)
    instance_double(ActionDispatch::Request, remote_ip: addr)
  end

  # One submission's worth of throttle bookkeeping, in its own request-scoped cache lifecycle.
  def submission(target = form)
    store.with_local_cache { controller.send(:submission_throttled?, target) }
  end

  it 'permits submissions up to the limit, then refuses the excess' do
    expect(Array.new(5) { submission }).to eq([false, false, false, true, true])
  end

  it 'keeps the running count in the underlying store between requests' do
    3.times { submission }

    expect(store.read("cama_contact_form_submit:#{site.id}:#{ip}:#{form.id}", raw: true).to_i).to eq(3)
  end

  it 'keeps a separate budget per client IP' do
    3.times { submission } # this IP has reached the limit
    allow(controller).to receive(:request).and_return(request_from('203.0.113.9'))

    expect(submission).to be(false)
  end

  it 'keeps a separate budget per form' do
    3.times { submission } # this IP has reached the limit for `form`
    other = build_form(fields: [text_field(field_type: 'email')], slug: 'contact-2', name: 'Second')

    expect(submission(other)).to be(false)
  end

  # The endpoint's half of the contract: given a verdict, `save_form` refuses before it processes, and
  # tells the visitor why. The verdict itself is exercised above; here it is fixed so the branch is
  # what is under test, not the counter.
  describe 'save_form acting on the verdict' do
    before { publish_form_on_sample_post }

    def post_submission
      post '/plugins/cama_contact_form/save_form', params: { id: form.id, fields: { c1: 'visitor@example.com' } }
    end

    it 'refuses a throttled submission before it writes a row, and says why' do
      allow_any_instance_of(Plugins::CamaContactForm::FrontController)
        .to receive(:submission_throttled?).and_return(true)

      expect { post_submission }.not_to(change { form.responses.count })
      expect(flash[:contact_form][:error]).to include('Too many')
    end

    it 'processes a submission the throttle allows through' do
      allow_any_instance_of(Plugins::CamaContactForm::FrontController)
        .to receive(:submission_throttled?).and_return(false)

      post_submission

      expect(flash[:contact_form][:error].to_s).not_to include('Too many')
    end
  end
end
