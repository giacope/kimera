# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# K3-3: warm workers re-ran the before(:suite) hooks the parent had run; a
# hook that is not idempotent then broke every test, and kimera dropped them
# as "failing tests that cover no in-scope mutant", leaving false survivors.
RSpec.describe("kimera run on a suite whose hooks misbehave under kimera (end-to-end)", :aggregate_failures) do
  def project(root, files)
    {
      "app/calc.rb" => "class Calc\n  def positive?(n) = n > 0\nend\n",
      "spec/spec_helper.rb" => <<~RUBY
        require_relative "../app/calc"
        LOG = File.expand_path("../hooks.log", __dir__)
        module Factory
          def build = Calc.new
        end
        RSpec.configure do |config|
          config.include(Factory)
          config.before(:suite) do
            File.write(LOG, "ran\\n", mode: "a")
            Factory.module_eval do
              alias_method(:build_once, :build)
              def build = build_once
            end
          end
        end
      RUBY
    }.merge(files).each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), body)
    end
  end

  def calculator = <<~RUBY
    require_relative "spec_helper"
    RSpec.describe(Calc) do
      it("is positive above zero") { expect(build.positive?(1)).to be(true) }
      it("is not positive at zero") { expect(build.positive?(0)).to be(false) }
    end
  RUBY

  # The run over the calculator's spec and the given files, and its project root.
  def hooked(files, *arguments)
    Dir.mktmpdir("kimera-hooks") do |root|
      project(root, { "spec/calc_spec.rb" => calculator }.merge(files))
      yield(test_outcome(cwd: root, arguments: arguments), root)
    end
  end

  def outside = <<~RUBY
    require_relative "spec_helper"
    RSpec.describe("plain") { it("runs outside kimera") { expect($PROGRAM_NAME).not_to end_with("kimera") } }
  RUBY

  def failing = <<~RUBY
    require_relative "spec_helper"
    RSpec.describe("red") { it("fails anywhere") { expect(1).to eq(2) } }
  RUBY

  it "runs the suite's hooks once, so two workers kill what one does" do
    hooked({}, "--jobs", "2") do |run, root|
      expect([run.statuses, run.status]).to(eq([["killed"], 0]), run.output)
      expect(File.read(File.join(root, "hooks.log"))).to(eq("ran\n"))
    end
  end

  it "stops with a harness error when a test fails only under kimera" do
    hooked({ "spec/plain_spec.rb" => outside }) do |run|
      expect(run.output).to(
        include("harness error: 1 test(s) fail under kimera but pass in a plain run", "./spec/plain_spec.rb[1:1]")
      )
      expect(run.status).to(eq(1))
    end
  end

  it "excludes a test that fails plainly too, saying its coverage is unknown" do
    hooked({ "spec/red_spec.rb" => failing }) do |run|
      expect(run.output).to(include("1 test(s) fail in the baseline, in a plain run too", "their coverage is unknown"))
      expect([run.statuses, run.status]).to(eq([["killed"], 0]))
    end
  end
end
