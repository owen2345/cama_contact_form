# frozen_string_literal: true

# The submission throttle and the attachment cap read their thresholds through one parser
# (`positive_site_option`), so its contract is pinned once here and included per option wiring.
# camaleon_cms's set_option runs values through String#to_var, so what comes back is not always the
# integer a naive `.to_i` assumed: a "true"/"false" option is a boolean (`false.to_i` raises), a
# cleared one is nil, a stray "unlimited"/0 would refuse everything site-wide, and a non-canonical
# numeral ("07", "0x10") survives as a String, where a bare Integer() would apply radix prefixes.
# Only a positive integer is accepted; everything else falls back to the default.
#
# Hosts provide `site` and an `effective_limit` reading the limit under test.
RSpec.shared_examples 'a positive-integer limit option' do |option:, default:|
  it 'honours a positive integer option' do
    site.set_option(option, 3)
    expect(effective_limit).to eq(3)
  end

  it 'falls back to the default when the option is unset' do
    expect(effective_limit).to eq(default)
  end

  it 'falls back to the default for 0 rather than refusing everything site-wide' do
    site.set_option(option, 0)
    expect(effective_limit).to eq(default)
  end

  it 'falls back to the default for a non-numeric string' do
    site.set_option(option, 'unlimited')
    expect(effective_limit).to eq(default)
  end

  it 'does not raise when the option was coerced to a boolean' do
    site.set_option(option, 'false')

    expect { effective_limit }.not_to raise_error
    expect(effective_limit).to eq(default)
  end

  it 'reads a leading-zero string as decimal rather than octal, and rejects a radix prefix' do
    site.set_option(option, '07')
    expect(effective_limit).to eq(7)

    site.set_option(option, '0x10')
    expect(effective_limit).to eq(default)
  end
end
