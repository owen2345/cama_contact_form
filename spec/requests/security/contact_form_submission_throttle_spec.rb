# frozen_string_literal: true

# `save_form` is public, unauthenticated, and -- unless the form happens to carry a captcha field --
# unthrottled, so a script can mail-bomb the owner (and the auto-reply), fill
# `public/contact_form/<site_id>` with uploads, and flood the responses table. Submissions are now
# capped per client IP per form in a fixed window, and the excess is refused before any mail, upload
# or row is written -- a hard cap rather than a captcha challenge, so a form that carries no captcha is
# still protected.
#
# The budget is spent by `record_submission` only once a row is stored, and read back by
# `submission_over_limit?` before the next submission does any work. `over_limit?`/`record` below drive
# each through its own `with_local_cache`, the way Rails scopes a request's cache and discards it at
# the end: the count has to survive in the *underlying* store once the request-scoped cache is torn
# down, or a second request would never see the first.
RSpec.describe 'Security: contact form submission throttle' do
  include ActiveSupport::Testing::TimeHelpers

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

  # A read of the verdict, in its own request-scoped cache lifecycle.
  def over_limit?(target = form)
    store.with_local_cache { controller.send(:submission_over_limit?, target) }
  end

  # One stored submission's worth of bookkeeping, in its own request-scoped cache lifecycle.
  def record(target = form)
    store.with_local_cache { controller.send(:record_submission, target) }
  end

  it 'permits stored submissions up to the limit, then reports the excess over limit' do
    verdicts = Array.new(5) do
      over = over_limit?
      record unless over
      over
    end

    expect(verdicts).to eq([false, false, false, true, true])
  end

  it 'keeps the running count in the underlying store between requests' do
    3.times { record }

    expect(store.read("cama_contact_form_submit:#{site.id}:#{ip}:#{form.id}", raw: true).to_i).to eq(3)
  end

  it 'keeps a separate budget per client IP' do
    3.times { record } # this IP has reached the limit
    allow(controller).to receive(:request).and_return(request_from('203.0.113.9'))

    expect(over_limit?).to be(false)
  end

  it 'keeps a separate budget per form' do
    3.times { record } # this IP has reached the limit for `form`
    other = build_form(fields: [text_field(field_type: 'email')], slug: 'contact-2', name: 'Second')

    expect(over_limit?(other)).to be(false)
  end

  it 'resets the budget once the fixed window elapses' do
    3.times { record }
    expect(over_limit?).to be(true)

    window = Plugins::CamaContactForm::ContactFormControllerConcern::SUBMISSION_THROTTLE_WINDOW
    travel(window + 1.minute) do
      expect(over_limit?).to be(false)
    end
  end

  # The half of the contract the counter alone cannot prove: a submission that never stores a row --
  # here one that fails required-field validation -- must not spend budget, or a bot's zero-cost
  # failures would lock out a co-NAT visitor whose own submission is valid.
  describe 'counting only stored submissions', type: :request do
    before { site.set_option('contact_form_max_submits', 1) }

    it 'does not charge a submission that fails validation' do
      submit_contact_form(form, { c1: '' })            # required field missing -> no row, no charge
      submit_contact_form(form, { c1: 'a@example.com' }) # valid -> stored, spends the only unit
      submit_contact_form(form, { c1: 'b@example.com' }) # over limit now -> refused

      expect(form.responses.count).to eq(1)
    end
  end

  # The endpoint's half of the contract: given a verdict, `save_form` refuses before it processes, or
  # stores and says nothing about limits. The verdict itself is exercised above; here it is fixed so
  # the branch is what is under test, not the counter.
  describe 'save_form acting on the over-limit verdict', type: :request do
    def stub_over_limit(verdict)
      allow_any_instance_of(Plugins::CamaContactForm::FrontController)
        .to receive(:submission_over_limit?).and_return(verdict)
    end

    it 'refuses an over-limit submission before it writes a row, and says why' do
      stub_over_limit(true)

      expect { submit_contact_form(form, { c1: 'visitor@example.com' }) }
        .not_to(change { form.responses.count })
      expect(flash[:contact_form][:error]).to include('Too many')
    end

    it 'stores a submission the throttle allows through' do
      stub_over_limit(false)

      expect { submit_contact_form(form, { c1: 'visitor@example.com' }) }
        .to change { form.responses.count }.by(1)
      expect(flash[:contact_form][:error].to_s).not_to include('Too many')
    end
  end
end
