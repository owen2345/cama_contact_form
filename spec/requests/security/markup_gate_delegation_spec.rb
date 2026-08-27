# frozen_string_literal: true

require 'rails_helper'

# The seam between the plugin's markup gate and the core detector it delegates to
# (CamaleonCms::UnsafeMarkup). These are unit checks of the wiring, not full request flows.
RSpec.describe 'Security: markup gate delegation' do
  let(:controller_class) { Plugins::CamaContactForm::AdminFormsController }

  describe 'compatible core requirement' do
    # The floor cannot live in the gemspec (camaleon_cms depends on this gem, so a reverse pin would
    # be circular), so the plugin verifies the core version at load and fails with an actionable
    # message instead of a broken gate or an ineffective throttle at the first untrusted request.
    it 'is satisfied in this environment' do
      expect(controller_class.compatible_core?).to be(true)
      expect { controller_class.ensure_compatible_core! }.not_to raise_error
    end

    it 'fails closed with an actionable error against an incompatible core' do
      allow(controller_class).to receive(:compatible_core?).and_return(false)

      expect { controller_class.ensure_compatible_core! }
        .to raise_error(/requires camaleon_cms >= 2\.9\.4/)
    end
  end

  describe 'TRANSLATION_MARKER' do
    # rendered_forms strips markers to build the form the renderer emits, while the detector scans
    # around markers; if the two grammars drifted, a payload split across a marker could slip the
    # gate. Reusing the detector's own constant makes that drift impossible -- same object, not a copy.
    it "is the core detector's constant, not a re-spelled copy" do
      expect(controller_class::TRANSLATION_MARKER).to equal(CamaleonCms::UnsafeMarkup::TRANSLATION_MARKER)
    end
  end
end
