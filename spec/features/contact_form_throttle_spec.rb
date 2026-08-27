# frozen_string_literal: true

# End to end: a visitor at a real browser submits the form on a frontend page repeatedly, and
# the (N+1)th submission is refused before any response row is written. This drives the whole stack —
# the rendered shortcode form, the POST, the Rails.cache counter accumulating across genuinely
# separate requests, and the refusal flash on the redisplayed page — so it is the proof the unit-level
# lifecycle specs (spec/requests/security/contact_form_submission_throttle_spec.rb) cannot give.
#
# Observable only on camaleon_cms >= 2.9.4: on earlier cores the default-on front_cache plugin ran
# `Rails.cache.clear` on every frontend POST, so each submission wiped the counter it had just
# incremented and no flood could ever reach the limit (the Gemfile floor records this).
RSpec.describe 'the contact form submission throttle', :js do
  init_site

  let(:form) { build_form(fields: [text_field(label: 'Name')]) }

  before do
    # Small budget so the excess is one page-turn away; the default (10) only slows the proof down.
    @site.set_option('contact_form_max_submits', 2)
    form
    publish_form_on_sample_post
  end

  def submit(value)
    fill_in 'fields[c1]', with: value
    click_button 'Send'
  end

  it 'lets a visitor submit up to the limit, then refuses the excess before a row is written' do
    visit @post.the_url(as_path: true)
    expect(page).to have_button('Send')

    2.times do |n|
      submit("visitor #{n}")
      expect(page).to have_text('Your message has been sent successfully')
    end

    submit('the flood')

    expect(page).to have_text('Too many submissions from your network')
    # Refused before the response row, not after: only the two allowed submissions were stored.
    expect(form.responses.count).to eq(2)
  end
end
