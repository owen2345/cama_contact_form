# frozen_string_literal: true

require 'capybara/rspec'
require 'capybara-screenshot/rspec'
require 'selenium-webdriver'

# Headless Chrome for :js feature specs. Unlike camaleon_cms's dummy, the Chrome version is not
# pinned: Selenium Manager (bundled with selenium-webdriver) resolves a chromedriver matching
# whatever Chrome is installed, so the same config works on a developer's machine and in CI.
Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless=new')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-gpu')
  options.add_argument('--disable-dev-shm-usage')
  # Workaround https://bugs.chromium.org/p/chromedriver/issues/detail?id=2650
  options.add_argument('--disable-site-isolation-trials')
  options.add_argument('--window-size=1400,1400')
  # Destructive admin actions raise a native confirm(); confirm_dialog drives it explicitly, so tell
  # Chrome not to auto-dismiss the dialog out from under the driver.
  options.unhandled_prompt_behavior = 'ignore'
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.javascript_driver = :selenium_chrome_headless

# Selenium's native element.clear does not reliably empty a pre-filled input on headless Chrome, so
# fill_in would type onto the existing value. Clearing via backspace is reliable. (camaleon_cms #1246.)
Capybara.default_set_options = { clear: :backspace }

# Save a screenshot beside the failure when a :js example fails; keep only the last run's.
Capybara::Screenshot.register_driver(:selenium_chrome_headless) do |driver, path|
  driver.browser.save_screenshot(path)
end
Capybara::Screenshot.prune_strategy = :keep_last_run
