# frozen_string_literal: true

# The throttle threshold is the `contact_form_max_submits` site option. camaleon_cms stores option
# values through String#to_var, so the value that comes back is not always the integer the naive
# `.to_i` assumed: a "true"/"false" option is a boolean (`false.to_i` raises NoMethodError, 500-ing
# every submission), a cleared option is nil, and a stray "unlimited"/0 would coerce to 0 and refuse
# every submission site-wide. The limit reader now accepts only a positive integer and otherwise
# falls back to the default, so a mistyped option can neither crash the endpoint nor brick the form.
RSpec.describe 'Security: contact form throttle limit option' do
  let(:controller) { Plugins::CamaContactForm::FrontController.new }

  before { allow(controller).to receive(:current_site).and_return(site) }

  def effective_limit
    controller.send(:submission_limit)
  end

  it 'honours a positive integer option' do
    site.set_option('contact_form_max_submits', 3)
    expect(effective_limit).to eq(3)
  end

  it 'falls back to the default when the option is unset' do
    expect(effective_limit).to eq(10)
  end

  it 'falls back to the default for 0 rather than refusing every submission' do
    site.set_option('contact_form_max_submits', 0)
    expect(effective_limit).to eq(10)
  end

  it 'falls back to the default for a non-numeric string' do
    site.set_option('contact_form_max_submits', 'unlimited')
    expect(effective_limit).to eq(10)
  end

  it 'does not raise when the option was coerced to a boolean' do
    site.set_option('contact_form_max_submits', 'false')

    expect { effective_limit }.not_to raise_error
    expect(effective_limit).to eq(10)
  end
end
