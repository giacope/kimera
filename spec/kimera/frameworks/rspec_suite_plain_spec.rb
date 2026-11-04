# frozen_string_literal: true

require "json"
require "kimera/frameworks/rspec_suite"
require "tmpdir"

# F9: a test red only under kimera is rerun outside it before kimera trusts it.
RSpec.describe(Kimera::Frameworks::RSpecSuite, :aggregate_failures) do
  describe "rerunning baseline failures without kimera" do
    # Some tests of a suite of two examples in one file, past the loading this spec skips.
    def selected(*ids) = described_class::Selection.new(ids, %w[./a_spec.rb[1:1] ./a_spec.rb[1:2]].to_h { [it, nil] })

    it "reruns the known ids through the bundle with a JSON report, in the order given" do
      expect(selected("./a_spec.rb[1:2]", "./gone_spec.rb[1:1]").plain("/out.json")).to(
        eq(%w[bundle exec rspec --format json --out /out.json --order defined ./a_spec.rb[1:2]])
      )
    end

    it "calls rspec itself outside a bundle" do
      hide_const("Bundler")
      expect(selected("./a_spec.rb[1:1]").plain("/out.json").first(2)).to(eq(%w[rspec --format]))
    end

    # The failed ids read from a JSON report with this body, or from none.
    def reported(body)
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out.json")
        File.write(out, body) if body
        selected.failed("", out)
      end
    end

    it "reads the failed examples' ids from the JSON report" do
      examples = [{ "id" => "a[1:1]", "status" => "failed" }, { "id" => "a[1:2]", "status" => "passed" }]
      expect(reported(JSON.generate("examples" => examples))).to(eq(["a[1:1]"]))
    end

    it "fails when there is no report, or it does not parse" do
      expect { reported(nil) }.to(raise_error(Errno::ENOENT))
      expect { reported("{") }.to(raise_error(JSON::ParserError))
    end
  end
end
