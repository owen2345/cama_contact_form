# frozen_string_literal: true

# End to end: a visitor submits the form rendered on a frontend page repeatedly, and the (N+1)th
# submission is refused before any response row is written. This drives the whole stack -- the rendered
# shortcode form, the routed POSTs, the Rails.cache counter accumulating across genuinely separate
# requests (each click is a full trip through the middleware, front_cache included), and the refusal
# flash on the redisplayed page -- so it is the proof the unit-level lifecycle specs
# (spec/requests/security/contact_form_submission_throttle_spec.rb) cannot give.
#
# The flow is a plain server-rendered form POST with no JavaScript, so it runs on the default rack_test
# driver: synchronous, so there is no page-turn race between two byte-identical success pages, and no
# headless browser to start.
#
# Observable only on camaleon_cms >= 2.9.4: earlier releases wiped Rails.cache on every frontend POST
# (the default-on front_cache plugin), so each submission erased the counter it had just incremented
# and no flood could reach the limit (the Gemfile floor records this).
RSpec.describe 'the contact form submission throttle' do
  init_site

  let(:form) { build_form(fields: [text_field(label: 'Name')]) }

  before do
    # Small budget so the excess is one submission away; the default (10) only slows the proof down.
    @site.set_option('contact_form_max_submits', 2)
    form
    publish_form_on_sample_post
  end

  # A fresh page load per submission, so each interaction acts on the page the previous POST redirected
  # to rather than a stale one.
  def submit(value)
    visit @post.the_url(as_path: true)
    fill_in 'fields[c1]', with: value
    click_button 'Send'
  end

  it 'lets a visitor submit up to the limit, then refuses the excess before a row is written' do
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
