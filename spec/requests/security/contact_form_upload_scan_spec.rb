# frozen_string_literal: true

# Pins the defence that stands between an anonymous contact-form upload and an active file in the
# CMS origin: camaleon_cms's content scanner, which `cama_tmp_upload` runs before the bytes reach
# the web-served `public/contact_form/<site_id>` path. There is no `formats:` allowlist and there is
# no need for one -- the scan, not a file-type restriction, is the control, and the plugin floors
# camaleon_cms >= 2.9.4 (CoreCompatibility, enforced at boot) so the scanner is guaranteed present.
#
# A visitor is never `cama_trusted_for_unfiltered_upload?` (it reads CurrentRequest.user and fails
# closed), so every upload is scanned, routed by the extension the file will be *served* under:
# markup (`.html`, `.svg`) is parsed and refused when it carries active content, executable script
# (`.js`) is refused outright (no scan can judge it), and a clean file is stored byte-for-byte --
# reject-or-store-verbatim, never sanitised and never re-encoded.
#
# Red-first is infeasible by construction: reproducing the vulnerability needs a pre-2.9.4 core
# without the scanner, which the floor and the boot-time gate refuse to load. The scanner's own
# rules are exercised in camaleon_cms; this pins that this endpoint actually routes through it.
RSpec.describe 'Security: contact form upload content scan' do
  let(:form) { build_form(fields: [file_field]) }

  before { form }

  # Built from an in-memory body; the multipart round-trip turns it into the
  # ActionDispatch::Http::UploadedFile the shape gate and upload loop expect.
  def upload(content, filename, content_type)
    Rack::Test::UploadedFile.new(StringIO.new(content), content_type, original_filename: filename)
  end

  def stored_files
    Dir[Rails.public_path.join('contact_form', site.id.to_s, '**', '*').to_s].select { |p| File.file?(p) }
  end

  # The security-critical property for each refused upload: the bytes never land in the web-served
  # directory. cama_tmp_upload returns the scan error before it writes, so nothing is staged.
  it 'refuses an .html carrying <script>, writing no file to the served directory' do
    before_files = stored_files.size

    submit_contact_form(form, { c1: [upload('<script>alert(1)</script>', 'evil.html', 'text/html')] })

    expect(stored_files.size).to eq(before_files)
    expect(flash[:contact_form][:error]).to be_present
  end

  it 'refuses an .svg carrying an event handler, writing no file to the served directory' do
    before_files = stored_files.size
    svg = '<svg xmlns="http://www.w3.org/2000/svg"><a onload="alert(1)">x</a></svg>'

    submit_contact_form(form, { c1: [upload(svg, 'evil.svg', 'image/svg+xml')] })

    expect(stored_files.size).to eq(before_files)
    expect(flash[:contact_form][:error]).to be_present
  end

  # `.js` has no safe subset, so the scanner refuses it outright rather than parsing -- a visitor,
  # who can never hold media_unfiltered_upload, can never store executable script.
  it 'refuses an executable .js outright, writing no file to the served directory' do
    before_files = stored_files.size

    submit_contact_form(form, { c1: [upload('alert(document.cookie)', 'evil.js', 'application/javascript')] })

    expect(stored_files.size).to eq(before_files)
    expect(flash[:contact_form][:error]).to be_present
  end

  # The other half of reject-or-store-verbatim: a clean file passes and is stored exactly as
  # uploaded -- no sanitising pass rewrites it, and no formats allowlist refuses a type the scan
  # cleared.
  it 'accepts a clean .svg and stores it byte-for-byte' do
    svg = '<svg xmlns="http://www.w3.org/2000/svg"><rect width="1" height="1"/></svg>'
    before_files = stored_files

    expect { submit_contact_form(form, { c1: [upload(svg, 'logo.svg', 'image/svg+xml')] }) }
      .to change { form.responses.count }.by(1)

    new_files = stored_files - before_files
    expect(new_files.size).to eq(1)
    expect(File.binread(new_files.first)).to eq(svg)
  end
end
