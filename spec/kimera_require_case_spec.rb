# frozen_string_literal: true

RSpec.describe(Kimera) do
  def test_features
    Dir[File.expand_path("../lib/**/*.rb", __dir__)].flat_map do |file|
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

  it "spells every library require with its on-disk case" do
    expect(test_features.filter_map { |feature| test_wrong_case(feature) }).to(eq([]))
  end
end
