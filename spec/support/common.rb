# frozen_string_literal: true

# Spec helpers adapted from camaleon_cms's spec/support/common.rb. Only the helpers the contact_form
# specs actually use are ported.

# Expose the suite-wide shared site (spec/support/shared_site.rb) as @site, along with its sample
# post. fresh: true replaces it with a site created inside the example's transaction.
def init_site(fresh: false)
  before do
    if fresh
      CamaleonCms::Site.delete_all
      @site = create(:site).decorate
    else
      @site = (CamaleonCms::Site.first || create(:site)).decorate
    end
    @post = @site.the_post('sample-post').decorate
  end

  after do
    @site = nil
    @post = nil
  end
end

# Sign in to the admin panel by setting the auth cookie directly (the browser must be on the app's
# origin to accept it, hence the static bootstrap visit). Feature specs only; the password is still
# verified so a wrong one fails loudly instead of producing a silently signed-out session.
def admin_sign_in(username = 'admin', pass = 'admin123')
  user = CamaManager.get_user_class_name.constantize.find_by!(username: username)
  raise ArgumentError, "wrong password for #{username}" unless user.authenticate(pass)

  visit '/favicon.ico' unless page.current_url.start_with?('http')
  page.driver.browser.manage.add_cookie(name: 'auth_token', value: "#{user.auth_token}&rspec&127.0.0.1")
end

def cama_root_relative_path
  PluginRoutes.system_info['relative_url_root'].presence&.to_s
end

# Accept the native JS confirm() dialog a destructive admin action raises. The dialog can lag a beat
# behind the click, so poll for it up to Capybara's default wait rather than assuming it is already up.
def confirm_dialog
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Capybara.default_max_wait_time
  begin
    page.driver.browser.switch_to.alert.accept
  rescue Selenium::WebDriver::Error::NoSuchAlertError
    raise if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

    sleep 0.1
    retry
  end
end
