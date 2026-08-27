# frozen_string_literal: true

# Two visitors submitting forms on the same site within the same wall-clock second used to collide:
# the response row's name was stamped only to the second, `before_validating` parameterizes the name
# into the slug, and the site-scoped slug-uniqueness validation refused the second response with the
# generic "an error occurred" -- a correctly filled submission was silently lost. Caught by the
# end-to-end throttle spec, whose consecutive submissions land in the same second on any fast
# machine. `freeze_time` pins the clock, so both submissions are stamped identically -- the exact
# collision.
RSpec.describe 'contact form responses submitted in the same second' do
  include ActiveSupport::Testing::TimeHelpers

  let(:form) { build_form(fields: [text_field(label: 'Name')]) }

  it 'stores every response, not just the first' do
    freeze_time do
      submit_contact_form(form, { c1: 'first visitor' })
      submit_contact_form(form, { c1: 'second visitor' })
    end

    expect(form.responses.count).to eq(2)
  end
end
