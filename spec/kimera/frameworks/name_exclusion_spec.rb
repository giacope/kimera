# frozen_string_literal: true

require "kimera/frameworks/adapter"
require "kimera/frameworks/name_exclusion"

# rack's one test that fails as root covered in-scope mutants; leaving out
# its whole file dropped 26 more tests.
RSpec.describe(Kimera::Frameworks::NameExclusion, :aggregate_failures) do
  let(:adapter) do
    Class.new(Kimera::Frameworks::Adapter) do
      def test_ids = %w[./dir_spec.rb[1:1] ./dir_spec.rb[1:2] ./other_spec.rb[1:1]]
      def describe(id)
        { "./dir_spec.rb[1:1]" => "Directory serves a file", "./dir_spec.rb[1:2]" => "Directory 404s unreadable" }[id]
      end
      def run(ids) = ids
    end.new
  end

  it "leaves out the tests whose name matches, keeping the rest of their file" do
    kept = described_class.new(adapter, ["unreadable"]).test_ids
    expect(kept).to(eq(%w[./dir_spec.rb[1:1] ./other_spec.rb[1:1]]))
  end

  it "matches a test's id too, and passes everything else through" do
    excluding = described_class.new(adapter, ["other_spec", "^nothing$"])
    expect(excluding.test_ids).to(eq(%w[./dir_spec.rb[1:1] ./dir_spec.rb[1:2]]))
    expect(excluding.run(["x"])).to(eq(["x"]))
  end
end
