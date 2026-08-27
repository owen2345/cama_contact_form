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
  let(:form) { build_form(fields: [file_field]) }

  # Every recipient handed to the mailer -- proving both absence (nothing sent on refusal) and that
  # the owner mail was attempted on the boundary.
  let(:sent_to) { spy_on_mail_recipients }

  before do
    form
    sent_to
  end

  def stored_files
    Dir[Rails.public_path.join('contact_form', site.id.to_s, '**', '*').to_s].select { |p| File.file?(p) }
  end

  it 'refuses a submission carrying more files than the default cap, before any upload, row or mail' do
    rows = form.responses.count
    files = stored_files.size

    submit_contact_form(form, { c1: png_uploads(6) })

    expect(form.responses.count).to eq(rows)
    expect(stored_files.size).to eq(files)
    expect(sent_to).to be_empty
    expect(flash[:contact_form][:error]).to include('maximum 5')
  end

  it 'stores a submission at exactly the cap, files and notification mail included' do
    site.set_option('contact_form_max_files', 2)
    rows = form.responses.count
    files = stored_files.size

    submit_contact_form(form, { c1: png_uploads(2) })

    expect(form.responses.count).to eq(rows + 1)
    expect(stored_files.size).to eq(files + 2)
    expect(sent_to).to eq(['owner@example.com'])
  end

  # The refusal must survive its own redisplay: the refused files used to ride along in
  # flash[:values], and enough of them serialized the session cookie past its 4KB limit --
  # ActionDispatch::Cookies::CookieOverflow, a 500 in place of the message -- so the stash now
  # drops file values (a file input always redisplays empty anyway).
  it 'refuses a far-over-cap submission with the message, not a session-cookie overflow' do
    expect { submit_contact_form(form, { c1: png_uploads(10) }) }.not_to raise_error

    expect(flash[:contact_form][:error]).to include('Too many files')
    expect(flash[:values].to_unsafe_h).not_to have_key('c1')
  end

  it 'honours a lowered contact_form_max_files option' do
    site.set_option('contact_form_max_files', 2)

    expect { submit_contact_form(form, { c1: png_uploads(3) }) }.not_to(change { form.responses.count })
    expect(flash[:contact_form][:error]).to include('maximum 2')
  end

  # The cap is a per-submission budget, so it sums across file fields -- a per-field cap would
  # multiply by however many file fields the form happens to carry.
  it 'counts the total across every file field of the form' do
    two_field_form = build_form(name: 'Two', slug: 'two',
                                fields: [file_field(label: 'A'), file_field(cid: 'c2', label: 'B')])
    site.set_option('contact_form_max_files', 2)

    expect do
      submit_contact_form(two_field_form, { c1: png_uploads(2), c2: png_uploads(1) })
    end.not_to(change { two_field_form.responses.count })
    expect(flash[:contact_form][:error]).to include('maximum 2')
  end

  # The under-cap sibling of the refuse-whole rule: a submission whose file fails its own upload
  # (core's size cap, the content scan) still stores and mails, and used to report unqualified
  # success -- the dropped file silently trimmed. The upload error now rides along with the notice.
  it 'reports a failed upload alongside the success message instead of swallowing it' do
    allow_any_instance_of(Plugins::CamaContactForm::FrontController)
      .to receive(:cama_tmp_upload).and_return({ error: 'File size limit exceeded' })

    expect { submit_contact_form(form, { c1: png_uploads(1) }) }.to change { form.responses.count }.by(1)

    expect(flash[:contact_form][:notice]).to be_present
    expect(flash[:contact_form][:error]).to include('File size limit exceeded')
  end

  # The refusal message is author-customizable through the `invalid_files_count` form message, like
  # the content gate's `invalid_content` -- which takes two halves: the editor's permit must keep
  # the key (an unlisted key is stripped from every save, erasing the message however it was set),
  # and the custom text must be able to carry the limit (`the_message` returns it verbatim, so the
  # %{max} substitution runs on the resolved message).
  describe 'customizing the refusal message' do
    it 'renders the custom message with the limit substituted' do
      custom = build_form(name: 'Custom', slug: 'custom', fields: [file_field],
                          settings: { 'railscf_message' => { 'invalid_files_count' => 'At most %{max} files!' } })

      submit_contact_form(custom, { c1: png_uploads(6) })

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

  # The threshold parser's contract lives in the shared group (spec/support/shared_limit_option.rb);
  # this wires it to `contact_form_max_files` and its default.
  describe 'the effective limit' do
    let(:controller) { Plugins::CamaContactForm::FrontController.new }

    before { allow(controller).to receive(:current_site).and_return(site) }

    def effective_limit
      controller.send(:attachment_limit)
    end

    it_behaves_like 'a positive-integer limit option', option: 'contact_form_max_files', default: 5
  end
end
