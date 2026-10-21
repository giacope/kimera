# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# R3K8: a run that deletes the project's files fails, naming them.
RSpec.describe("kimera run on a suite that deletes a project file (end-to-end)", :aggregate_failures) do
  it "fails the run and names the file" do
    Dir.mktmpdir("kimera-tree") do |root|
      FileUtils.mkdir_p(File.join(root, "app"))
      FileUtils.mkdir_p(File.join(root, "spec"))
      File.write(File.join(root, "fixture.rb"), "keep me\n")
      File.write(File.join(root, "app/calc.rb"), "class Calc\n  def self.big?(n) = n > 10\nend\n")
      File.write(File.join(root, "spec/calc_spec.rb"), <<~RUBY)
        require_relative "../app/calc"
        RSpec.describe(Calc) do
          it("is big") { expect(Calc.big?(11)).to be(true) }
          it("is small") { expect(Calc.big?(10)).to be(false) }
          it("cleans up") { File.delete(File.expand_path("../fixture.rb", __dir__)) if Calc.big?(5) }
        end
      RUBY
      test_run(cwd: root) do |output, _report, status|
        expect(output).to(include("kimera: the run changed 1 tracked file(s) in the project"))
        expect(output).to(include("\n  fixture.rb"))
        expect(status).to(eq(1))
      end
    end
  end
end
