# frozen_string_literal: true

# `require "english"` loads on a case-insensitive filesystem (macOS) and
# crashes at boot on Linux. Resolve every library require and insist the file
# found is spelled exactly like the feature, so the check bites on either host.
RSpec.describe("library requires") do
  def test_features
    Dir[File.expand_path("../../lib/**/*.rb", __dir__)].flat_map do |file|
      File.read(file, encoding: "UTF-8").scan(/^\s*require\s+["']([^"']+)["']/).flatten
    end.uniq
  end

  def test_wrong_case(feature)
    _kind, path = $LOAD_PATH.resolve_feature_path(feature)
    return "#{feature} (unresolvable)" unless path
    "#{feature} (resolves to #{path})" unless File.basename(path, ".*") == File.basename(feature)
  rescue LoadError
    "#{feature} (unresolvable)"
  end

  it "spells every required feature with its on-disk case" do
    expect(test_features.filter_map { |feature| test_wrong_case(feature) }).to(eq([]))
  end
end
