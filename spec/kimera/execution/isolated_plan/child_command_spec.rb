# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "kimera/execution/isolated_child_command"

# A mutant's child stops at its first failing test: any failure kills it. The
# baseline's child runs them all, so a red baseline names every failing test.
RSpec.describe(Kimera::Execution::IsolatedPlan::ChildCommand) do
  let(:two) { "RSpec.describe('two') { 2.times { |n| it(n.to_s) { expect(n).to(eq(-1)) } } }\n" }

  # The first example runs a failing group of its own on the shared reporter,
  # as a spec of an RSpec extension does; only the second fails itself.
  let(:nested) do
    <<~RUBY
      RSpec.describe("outer") do
        it("runs an inner suite") { RSpec::Core::ExampleGroup.describe { it { fail } }.run(RSpec.configuration.reporter) }
        it("fails") { fail }
      end
    RUBY
  end

  def failing(source, first_failure)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a_spec.rb"), source)
      ledger = File.join(dir, "ledger.json")
      File.write("#{ledger}.request", JSON.generate("tests" => ["./a_spec.rb"], "first_failure" => first_failure))
      env = { "BUNDLE_GEMFILE" => File.expand_path("../../../../Gemfile", __dir__) }
      child = [RbConfig.ruby, "-rbundler/setup", described_class::CHILD, ledger, "#{ledger}.request"]
      Open3.capture2e(env, *child, chdir: dir)
      JSON.parse(File.read(ledger)).values_at("failures", "failing")
    end
  end

  it "has the RSpec child stop at the first failing test when asked", :aggregate_failures do
    expect(failing(two, true)).to(eq([1, ["./a_spec.rb[1:1]"]]))
    expect(failing(two, false)).to(eq([2, ["./a_spec.rb[1:1]", "./a_spec.rb[1:2]"]]))
  end

  it "stops only for a failure of a test it was asked to run" do
    expect(failing(nested, true).last).to(include("./a_spec.rb[1:2]"))
  end
end
