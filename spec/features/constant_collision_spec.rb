# frozen_string_literal: true

RSpec.describe("kimera on a project that defines a constant named like kimera's internals (end-to-end)") do
  def tree
    examples = <<~RUBY
      require_relative "../app/mutant_runtime"

      RSpec.describe MutantRuntime do
        it("is active under a minute") { expect(MutantRuntime.active?(59)).to be(true) }
        it("is idle from a minute") { expect(MutantRuntime.active?(60)).to be(false) }
      end
    RUBY
    { "app/mutant_runtime.rb" => "class MutantRuntime\n  def self.active?(seconds)\n    seconds < 60\n  end\nend\n" }
      .merge("spec/mutant_runtime_spec.rb" => examples)
  end

  it "judges a top-level MutantRuntime like any other class" do
    run = test_tree(tree, "kimera-collision") { |root| test_outcome(cwd: root, arguments: %w[--jobs 1]) }
    expect([run.counts.values_at("total", "killed"), run.status]).to(eq([[2, 2], 0]), run.output)
  end
end
