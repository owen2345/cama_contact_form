# frozen_string_literal: true

require 'rails_helper'

# The seam between the plugin's markup gate and the camaleon_cms detector it delegates to
# (CamaleonCms::UnsafeMarkup). These are unit checks of the wiring, not full request flows.
RSpec.describe 'Security: markup gate delegation' do
  let(:controller_class) { Plugins::CamaContactForm::AdminFormsController }

  describe 'TRANSLATION_MARKER' do
    # rendered_forms strips markers to build the form the renderer emits, while the detector scans
    # around markers; if the two grammars drifted, a payload split across a marker could slip the
    # gate. Reusing the detector's own constant makes that drift impossible -- same object, not a copy.
    it "is the camaleon_cms detector's constant, not a re-spelled copy" do
      expect(controller_class::TRANSLATION_MARKER).to equal(CamaleonCms::UnsafeMarkup::TRANSLATION_MARKER)
    end
  end
end
