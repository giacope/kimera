# frozen_string_literal: true

require "open3"
require "tmpdir"

# giacope/kimera#6: a helper that gates its coverage floor on KIMERA, as the
# README advises, must pass every Kimera entry point without the caller
# exporting anything.
RSpec.describe("KIMERA in the suite's environment") do
  def project(dir)
    FileUtils.mkdir_p(File.join(dir, "app"))
    FileUtils.mkdir_p(File.join(dir, "spec"))
    File.write(File.join(dir, "app", "gate.rb"), "class Gate\n  def open?(n)\n    n > 1\n  end\nend\n")
    File.write(File.join(dir, "spec", "spec_helper.rb"), <<~RUBY)
      require "simplecov"
      SimpleCov.start do
        coverage_dir(File.join(#{dir.inspect}, "coverage"))
        minimum_coverage(line: 100) unless ENV["KIMERA"]
      end
      require_relative "../app/gate"
    RUBY
    File.write(File.join(dir, "spec", "gate_spec.rb"), <<~RUBY)
      require_relative "spec_helper"

      RSpec.describe(Gate) do
        it("opens above one") { expect(Gate.new.open?(2)).to(be(true)) }
        it("stays shut at one") { expect(Gate.new.open?(1)).to(be(false)) }
      end
    RUBY
  end

  def launch(dir, *)
    env = { "KIMERA" => nil, "BUNDLE_GEMFILE" => File.join(test_repo_root, "Gemfile") }
    command = [
      "bundle", "exec", "ruby", "-I", File.join(test_repo_root, "lib"),
      File.join(test_repo_root, "exe", "kimera")
    ]
    output, status = Open3.capture2e(env, *command, *, chdir: dir)
    [output.force_encoding(Encoding::UTF_8), status]
  end

  it "keeps a gated floor quiet in a warm run and in doctor", :aggregate_failures do
    Dir.mktmpdir("kimera-suite-env") do |dir|
      project(dir)
      output, status = launch(dir, "run", "app", "--tests", "spec/**/*_spec.rb", "--jobs", "1")
      expect(status.exitstatus).to(eq(0), output)
      expect(output).to(include("survived=0"))
      expect(output).not_to(include("SimpleCov failed"))

      output, = launch(dir, "doctor")
      expect(output).to(include("✓ Test loading: every test file loads"))
    end
  end
end
