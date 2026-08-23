# frozen_string_literal: true

# End-to-end smoke test: boots a camaleon_cms-backed dummy app with this plugin loaded, installs a
# Camaleon site, and asserts the contact_form plugin is live -- discovered by the CMS, activated for
# the site, backed by its table, and wired into the Site association its initializer adds.
RSpec.describe 'cama_contact_form plugin', type: :model do
  it 'loads the engine and top-level constant' do
    expect(defined?(CamaContactForm)).to eq('constant')
    expect(CamaContactForm::VERSION).to be_a(String)
    expect(CamaContactForm::Engine.ancestors).to include(Rails::Engine)
  end

  it 'ships its model backed by the plugins_contact_forms table' do
    expect(ActiveRecord::Base.connection.table_exists?('plugins_contact_forms')).to be(true)
    expect(Plugins::CamaContactForm::CamaContactForm.table_name).to eq('plugins_contact_forms')
  end

  it 'is discovered by Camaleon as a gem-mode plugin' do
    info = PluginRoutes.plugin_info('cama_contact_form')
    expect(info).to be_present
    expect(info['key']).to eq('cama_contact_form')
    expect(info['gem_mode']).to be(true)
  end

  it 'registers its front route so submissions can be posted' do
    expect(Rails.application.routes.url_helpers).to respond_to(:plugins_cama_contact_form_save_form_path)
  end

  describe 'with an installed Camaleon site' do
    let(:site) { create(:site) }

    it 'seeds a site with a working admin account' do
      expect(site).to be_persisted

      admin = site.users.find_by(role: 'admin')
      expect(admin).to be_present
      expect(admin.authenticate('admin123')).to be_truthy
    end

    it 'installs and activates the contact_form plugin for the site' do
      expect(site.plugins.pluck(:slug)).to include('cama_contact_form')
      expect(site.plugins.active.pluck(:slug)).to include('cama_contact_form')
    end

    it 'wires the Site#contact_forms association added by the plugin initializer' do
      form = site.contact_forms.create!(name: 'Contact us')

      expect(form).to be_a(Plugins::CamaContactForm::CamaContactForm)
      expect(form.slug).to eq('contact-us') # before_validation derives the slug from the name
      expect(site.contact_forms.reload).to include(form)
    end
  end
end
