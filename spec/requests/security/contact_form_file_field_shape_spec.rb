# frozen_string_literal: true

# The renderer encodes a file field as `fields[cid][]` file parts, and Rack drops an empty-filename
# part, so the only shapes a real form ever submits are an absent value or an array of uploaded
# files. `perform_save_form`'s upload loop assumed exactly that: any other shape -- a bare string, a
# nested hash, an array carrying a non-file entry -- raised NoMethodError (`String#to_a`,
# `original_filename`), an unauthenticated 500.
#
# The 500 was also the only thing standing between a forged entry and `cama_tmp_upload`, which
# treats a String argument as a URL to download or a local path to copy -- an anonymous visitor must
# never steer that. So a file field's value is now validated by shape before anything runs: absent,
# or an array whose every entry is an uploaded file, and anything else refuses the submission whole
# as an invalid request. Forged entries are refused, never coerced or filtered out -- passing a
# "cleaned" subset through would silently accept a request no real form produced.
RSpec.describe 'Security: contact form file field submission shape' do
  let(:form) do
    build_form(fields: [file_field, text_field(cid: 'c2', required: 'false')])
  end

  before do
    form
    # The proof that no forged entry can steer the uploader: reaching it at all fails the example.
    allow_any_instance_of(Plugins::CamaContactForm::FrontController)
      .to receive(:cama_tmp_upload).and_raise('cama_tmp_upload must not be reached by a forged file value')
  end

  def expect_refused_as_invalid_request
    expect(form.responses.count).to eq(0)
    expect(flash[:contact_form][:error]).to include('could not be submitted')
  end

  it 'refuses a bare string where the file array should be, without raising' do
    expect do
      submit_contact_form(form, { c1: 'https://192.0.2.9/internal.png', c2: 'x' })
    end.not_to raise_error

    expect_refused_as_invalid_request
  end

  it 'refuses an array carrying a non-file entry, without raising' do
    expect { submit_contact_form(form, { c1: ['https://192.0.2.9/internal.png'], c2: 'x' }) }.not_to raise_error

    expect_refused_as_invalid_request
  end

  it 'refuses a blank entry in the file array, which no real form part produces' do
    expect { submit_contact_form(form, { c1: [''], c2: 'x' }) }.not_to raise_error

    expect_refused_as_invalid_request
  end

  # `blank?` is not "absent": Rack drops the empty-filename part outright, so a real form yields
  # nil, never a present-but-blank value -- and a blank scalar raised in the upload loop like any
  # other forged shape.
  it 'refuses a blank scalar where the file array should be, without raising' do
    expect { submit_contact_form(form, { c1: '', c2: 'x' }) }.not_to raise_error

    expect_refused_as_invalid_request
  end

  it 'refuses a JSON false where the file array should be, without raising' do
    expect do
      post '/plugins/cama_contact_form/save_form',
           params: { id: form.id, fields: { c1: false, c2: 'x' } }, as: :json
    end.not_to raise_error

    expect(form.responses.count).to eq(0)
  end

  it 'refuses a nested hash where the file array should be, without raising' do
    expect { submit_contact_form(form, { c1: { nested: 'x' }, c2: 'x' }) }.not_to raise_error

    expect_refused_as_invalid_request
  end

  it 'refuses a single file submitted outside the array encoding' do
    expect { submit_contact_form(form, { c1: png_uploads.first, c2: 'x' }) }.not_to raise_error

    expect_refused_as_invalid_request
  end

  it 'still treats an absent file value as a submission with no attachments' do
    expect { submit_contact_form(form, { c2: 'just text' }) }.to change { form.responses.count }.by(1)

    expect(flash[:contact_form][:error]).to be_blank
  end
end
