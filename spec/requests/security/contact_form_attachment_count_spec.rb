# frozen_string_literal: true

# `save_form`'s file loop uploads and persists every entry submitted under a file field. Core bounds
# each file's size (`filesystem_max_size`), but nothing bounded how many entries one submission could
# carry -- the file input is `multiple` with no client-side cap, and the POST is public -- so a single
# anonymous request could stack arbitrarily many files onto `public/contact_form/<site_id>` and into
# a single notification mail. Submissions now carry a cap on the total number of attached files (the
# site-wide `contact_form_max_files` option), and an over-cap submission is refused whole in
# validation -- before any upload, row or mail -- never trimmed to the first N, which would silently
# drop files the visitor believes they sent.
RSpec.describe 'Security: contact form attachment count cap' do
  let(:form) do
    build_form(fields: [{ label: 'Docs', field_type: 'file', cid: 'c1', required: 'false', field_options: {} }])
  end

  # Every recipient handed to the mailer, captured at the seam `cama_send_email` calls -- the test
  # queue adapter enqueues `deliver_later` without performing, so `ActionMailer::Base.deliveries`
  # could prove absence but not that the owner mail was actually attempted (see
  # contact_form_auto_reply_recipient_spec.rb).
  let(:sent_to) { [] }

  before do
    form
    allow(CamaleonCms::HtmlMailer).to receive(:sender) do |recipient, *_|
      sent_to << recipient
      instance_double(ActionMailer::MessageDelivery, deliver_later: nil)
    end
  end

  def uploads(count)
    Array.new(count) do
      Rack::Test::UploadedFile.new(Rails.root.join('../support/fixtures/rails.png'), 'image/png')
    end
  end

  def stored_files
    Dir[Rails.public_path.join('contact_form', site.id.to_s, '**', '*').to_s].select { |p| File.file?(p) }
  end

  it 'refuses a submission carrying more files than the default cap, before any upload, row or mail' do
    rows = form.responses.count
    files = stored_files.size

    submit_contact_form(form, { c1: uploads(6) })

    expect(form.responses.count).to eq(rows)
    expect(stored_files.size).to eq(files)
    expect(sent_to).to be_empty
    expect(flash[:contact_form][:error]).to include('Too many files').and include('5')
  end

  it 'stores a submission at exactly the cap, files and notification mail included' do
    site.set_option('contact_form_max_files', 2)
    rows = form.responses.count
    files = stored_files.size

    submit_contact_form(form, { c1: uploads(2) })

    expect(form.responses.count).to eq(rows + 1)
    expect(stored_files.size).to eq(files + 2)
    expect(sent_to).to eq(['owner@example.com'])
  end

  # The refusal must survive its own redisplay: the refused files used to ride along in
  # flash[:values], and enough of them serialized the session cookie past its 4KB limit --
  # ActionDispatch::Cookies::CookieOverflow, a 500 in place of the message -- so the stash now
  # drops file values (a file input always redisplays empty anyway).
  it 'refuses a far-over-cap submission with the message, not a session-cookie overflow' do
    expect { submit_contact_form(form, { c1: uploads(10) }) }.not_to raise_error

    expect(flash[:contact_form][:error]).to include('Too many files')
    expect(flash[:values].to_unsafe_h).not_to have_key('c1')
  end

  it 'honours a lowered contact_form_max_files option' do
    site.set_option('contact_form_max_files', 2)

    expect { submit_contact_form(form, { c1: uploads(3) }) }.not_to(change { form.responses.count })
    expect(flash[:contact_form][:error]).to include('2')
  end

  # The cap is a per-submission budget, so it sums across file fields -- a per-field cap would
  # multiply by however many file fields the form happens to carry.
  it 'counts the total across every file field of the form' do
    two_field_form = build_form(name: 'Two', slug: 'two',
                                fields: [
                                  { label: 'A', field_type: 'file', cid: 'c1', required: 'false', field_options: {} },
                                  { label: 'B', field_type: 'file', cid: 'c2', required: 'false', field_options: {} }
                                ])
    site.set_option('contact_form_max_files', 2)

    expect do
      submit_contact_form(two_field_form, { c1: uploads(2), c2: uploads(1) })
    end.not_to(change { two_field_form.responses.count })
    expect(flash[:contact_form][:error]).to include('2')
  end

  # The refusal message is author-customizable through the `invalid_files_count` form message, like
  # the content gate's `invalid_content` -- which takes two halves: the editor's permit must keep
  # the key (an unlisted key is stripped from every save, erasing the message however it was set),
  # and the custom text must be able to carry the limit (`the_message` returns it verbatim, so the
  # %{max} substitution runs on the resolved message).
  describe 'customizing the refusal message' do
    it 'renders the custom message with the limit substituted' do
      custom = build_form(name: 'Custom', slug: 'custom',
                          fields: [{ label: 'Docs', field_type: 'file', cid: 'c1', required: 'false',
                                     field_options: {} }],
                          settings: { 'railscf_message' => { 'invalid_files_count' => 'At most %{max} files!' } })

      submit_contact_form(custom, { c1: uploads(6) })

      expect(flash[:contact_form][:error]).to include('At most 5 files!')
    end

    it 'is kept by the editor permit rather than stripped on save' do
      controller = Plugins::CamaContactForm::AdminFormsController.new
      controller.params = ActionController::Parameters.new(
        railscf_message: { 'invalid_files_count' => 'custom', 'bogus_key' => 'junk' }
      )

      expect(controller.send(:permitted_messages).to_h).to eq('invalid_files_count' => 'custom')
    end
  end

  # The threshold is a site option, and camaleon_cms stores option values through String#to_var --
  # the same trap `submission_limit` guards against (contact_form_throttle_limit_option_spec.rb):
  # only a positive integer is accepted, anything else falls back to the default rather than
  # 500-ing or refusing every attachment site-wide.
  describe 'the effective limit' do
    let(:controller) { Plugins::CamaContactForm::FrontController.new }

    before { allow(controller).to receive(:current_site).and_return(site) }

    def effective_limit
      controller.send(:attachment_limit)
    end

    it 'honours a positive integer option' do
      site.set_option('contact_form_max_files', 3)
      expect(effective_limit).to eq(3)
    end

    it 'falls back to the default when the option is unset' do
      expect(effective_limit).to eq(5)
    end

    it 'falls back to the default for 0 or a non-numeric string rather than refusing every file' do
      site.set_option('contact_form_max_files', 0)
      expect(effective_limit).to eq(5)

      site.set_option('contact_form_max_files', 'unlimited')
      expect(effective_limit).to eq(5)
    end
  end
end
