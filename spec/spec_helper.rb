# frozen_string_literal: true

# This file is loaded by every spec (via .rspec `--require spec_helper`) and stays framework-free.
# The Rails app is booted from rails_helper, which specs that need it require explicitly.
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
end
