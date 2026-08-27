# frozen_string_literal: true

# `save_form` looked its form up with `current_site.contact_forms.find_by(id:)`, and that association
# holds stored responses too (child rows, `parent_id` set). A response's `fields` is empty, so it
# passes validation, and submitting one wrote a fresh child row -- and, worse for the rate limit,
# opened that response id its own per-form throttle budget. An attacker walking the sequential,
# guessable response ids could therefore lap the flood cap and grow the table without bound. The
# lookup is now scoped to authored forms (`parent_id: nil`).
RSpec.describe 'Security: a stored response cannot be submitted as a form' do
  let(:form) { build_form(fields: [text_field(label: 'Name')]) }

  it 'refuses a stored response id and writes no further row' do
    submit_contact_form(form, { c1: 'first visitor' })
    response_row = form.responses.first
    expect(response_row).to be_present

    expect { submit_contact_form(response_row, { c1: 'attacker' }) }
      .not_to(change { site.contact_forms.count })

    expect(flash[:contact_form][:error]).to be_present
    expect(response_row.responses.count).to eq(0)
  end
end
