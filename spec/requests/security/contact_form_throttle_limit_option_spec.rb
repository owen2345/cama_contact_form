# frozen_string_literal: true

# The throttle threshold is the `contact_form_max_submits` site option, read through the shared
# positive-integer parser -- the contract itself is pinned in the shared group
# (spec/support/shared_limit_option.rb); this wires it to the throttle's option and default.
RSpec.describe 'Security: contact form throttle limit option' do
  let(:controller) { Plugins::CamaContactForm::FrontController.new }

  before { allow(controller).to receive(:current_site).and_return(site) }

  def effective_limit
    controller.send(:submission_limit)
  end

  it_behaves_like 'a positive-integer limit option', option: 'contact_form_max_submits', default: 10
end
