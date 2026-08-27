# frozen_string_literal: true

require 'rails_helper'

# The plugin needs camaleon_cms >= 2.9.4: CamaleonCms::UnsafeMarkup for the admin markup gate, and the
# front_cache fix (2.9.4 stopped wiping Rails.cache on every frontend POST) for the submission
# throttle to survive across requests. The floor can't live in the gemspec (camaleon_cms depends on
# this gem, so a reverse pin would be circular), so CoreCompatibility verifies it at boot from the
# engine initializer -- a seat every process passes through before serving, so a lazy-loaded
# FrontController#save_form can never run against an old core with a silently dead throttle. It fails
# closed with an actionable message.
RSpec.describe CamaContactForm::CoreCompatibility do
  it 'is satisfied in this environment' do
    expect(described_class.compatible_core?).to be(true)
    expect { described_class.ensure_compatible_core! }.not_to raise_error
  end

  it 'fails closed with an actionable error against an incompatible camaleon_cms' do
    allow(described_class).to receive(:compatible_core?).and_return(false)

    expect { described_class.ensure_compatible_core! }
      .to raise_error(/requires camaleon_cms >= 2\.9\.4/)
  end
end
