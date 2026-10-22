# frozen_string_literal: true

require "json"
require "kimera/frameworks/rspec_suite"
require "tmpdir"

# F9: a test red only under kimera is rerun outside it before kimera trusts it.
RSpec.describe(Kimera::Frameworks::RSpecSuite, :aggregate_failures) do
  describe "rerunning baseline failures without kimera" do
    let(:adapter) { described_class.allocate }

    before { allow(adapter).to(receive(:test_ids).and_return(%w[./a_spec.rb[1:1] ./a_spec.rb[1:2]])) }

    it "reruns the known ids through the bundle with a JSON report, in the order given" do
      expect(adapter.plain(%w[./a_spec.rb[1:2] ./gone_spec.rb[1:1]], "/out.json")).to(
        eq(%w[bundle exec rspec --format json --out /out.json --order defined ./a_spec.rb[1:2]])
      )
    end

    it "calls rspec itself outside a bundle" do
      hide_const("Bundler")
      expect(adapter.plain(%w[./a_spec.rb[1:1]], "/out.json").first(2)).to(eq(%w[rspec --format]))
    end

    it "reads the failed examples' ids from the JSON report, nothing when there is none" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out.json")
        examples = [{ "id" => "a[1:1]", "status" => "failed" }, { "id" => "a[1:2]", "status" => "passed" }]
        File.write(out, JSON.generate("examples" => examples))
        expect(adapter.failed_plainly("", out)).to(eq(["a[1:1]"]))
        expect(adapter.failed_plainly("", File.join(dir, "missing.json"))).to(eq([]))
        File.write(out, "{")
        expect(adapter.failed_plainly("", out)).to(eq([]))
      end
    end
  end
end
