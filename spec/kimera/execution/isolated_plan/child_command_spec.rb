# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "kimera/execution/isolated_child_command"

# A mutant's child stops at its first failing test: any failure kills it. The
# baseline's child runs them all, so a red baseline names every failing test.
RSpec.describe(Kimera::Execution::IsolatedPlan::ChildCommand) do
  def failing(first_failure)
    Dir.mktmpdir do |dir|
      two = "RSpec.describe('two') { 2.times { |n| it(n.to_s) { expect(n).to(eq(-1)) } } }\n"
      File.write(File.join(dir, "two_spec.rb"), two)
      ledger = File.join(dir, "ledger.json")
      File.write("#{ledger}.request", JSON.generate("tests" => ["./two_spec.rb"], "first_failure" => first_failure))
      child = described_class::CHILD
      env = { "BUNDLE_GEMFILE" => File.expand_path("../../../../Gemfile", __dir__) }
      Open3.capture2e(env, RbConfig.ruby, "-rbundler/setup", child, ledger, "#{ledger}.request", chdir: dir)
      JSON.parse(File.read(ledger)).values_at("failures", "failing")
    end
  end

  it "has the RSpec child stop at the first failing test when asked", :aggregate_failures do
    expect(failing(true)).to(eq([1, ["./two_spec.rb[1:1]"]]))
    expect(failing(false)).to(eq([2, ["./two_spec.rb[1:1]", "./two_spec.rb[1:2]"]]))
  end
end
