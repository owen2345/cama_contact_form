# frozen_string_literal: true

# A response's `before_destroy` (`delete_uploaded_files`) cleans up the files that response uploaded,
# which live in `public/contact_form/<site_id>`. It mapped each stored path onto the filesystem and
# deleted it with no confinement -- so a response whose stored path is absolute, or climbs out with
# `../`, deleted an arbitrary file the app process could write. That path is attacker-controlled when
# an admin imports an untrusted export (which stores response settings verbatim) and then any
# `:manage, :plugins` holder deletes the response -- a delete that is not admin-only.
#
# The cleanup is now confined to the site's own media root: each stored path is reduced to its
# basename and rebuilt inside `public/contact_form/<site_id>`, so a hostile path can at most name a
# file already sitting in that directory, never one outside it.
RSpec.describe 'Security: contact form response file cleanup confinement' do
  let(:form) do
    build_form(fields: [{ label: 'Doc', field_type: 'file', cid: 'c1', required: 'false', field_options: {} }])
  end

  def media_root
    Rails.public_path.join('contact_form', site.id.to_s)
  end

  # The exact base the delete sink strips from stored paths -- the same source, so a traversal built
  # on it is really mapped into the filesystem the way the old code did (a spec-local `cama_root_url`
  # can resolve to a different host and silently miss).
  def root_url
    Rails.application.routes.url_helpers.cama_root_url
  end

  # A stored response with an arbitrary file value under the form's file cid. Built directly: the
  # sink is what is under test, and this is the shape an untrusted import leaves behind.
  def stored_response(file_value)
    form.responses.create!(name: "response-#{SecureRandom.hex(4)}", site_id: form.site_id,
                           settings: { fields: { c1: file_value }, created_at: '2026-01-01' }.to_json)
  end

  it 'does not delete a file outside the media root named by an absolute stored path' do
    victim_dir = Dir.mktmpdir
    victim = File.join(victim_dir, 'victim.txt')
    File.write(victim, 'keep me')

    stored_response([victim]).destroy

    expect(File.exist?(victim)).to be(true)
  ensure
    FileUtils.remove_entry(victim_dir) if victim_dir
  end

  it 'does not delete a file reached by climbing out of the media root with ../' do
    FileUtils.mkdir_p(media_root) # the traversal resolves from an existing base, so it is a real red
    victim = Rails.public_path.join("victim-#{SecureRandom.hex(4)}.txt") # one level outside media_root
    File.write(victim, 'keep me')
    # Built the way perform_save_form stores a path (filesystem path -> URL), but with `../../`
    # climbing from contact_form/<site>/ back to public/, where the victim sits. The old delete
    # reversed exactly this mapping and resolved out of the root.
    fs_path = media_root.join('..', '..', victim.basename).to_s
    traversal = fs_path.sub(Rails.public_path.to_s, root_url)

    stored_response([traversal]).destroy

    expect(File.exist?(victim)).to be(true)
  ensure
    FileUtils.rm_f(victim) if victim
  end

  it "still deletes the response's own upload inside the media root" do
    FileUtils.mkdir_p(media_root)
    legit = media_root.join("upload-#{SecureRandom.hex(4)}.png")
    File.write(legit, 'x')
    # The URL form perform_save_form stores: cama_root_url + the public-relative path.
    stored = legit.to_s.sub(Rails.public_path.to_s, root_url)

    stored_response([stored]).destroy

    expect(File.exist?(legit)).to be(false)
  end

  it 'does not raise when the response settings carry no usable file value' do
    FileUtils.mkdir_p(media_root)

    expect { stored_response([nil, '', {}]).destroy }.not_to raise_error
    expect { stored_response('not-an-array').destroy }.not_to raise_error
  end
end
