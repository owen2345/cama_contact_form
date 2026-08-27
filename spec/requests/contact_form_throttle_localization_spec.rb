# frozen_string_literal: true

require 'rails_helper'

# The throttle refusal is shown to visitors, so it is localized like every other save_form message.
# English is the inline `default:` in the controller, but es and zh-CN carry the rest of the save_form
# strings -- and this one was missing from both, so a throttled visitor on those sites saw English
# amid otherwise translated messages.
RSpec.describe 'contact form throttle refusal localization' do
  key = 'plugins.cama_contact_form.front.save_form.too_many_requests'

  %i[es zh-CN].each do |locale|
    it "translates the throttle refusal in #{locale}" do
      expect(I18n.t(key, locale: locale, default: '__missing__')).not_to eq('__missing__')
    end
  end
end
