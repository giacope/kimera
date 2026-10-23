# frozen_string_literal: true

require "fileutils"
require "json"
require "kimera/execution/isolated_child_command"
require "open3"
require "rbconfig"
require "tmpdir"

# R4-KR5: maintenance_tasks' helper sets $VERBOSE and raises on every warning;
# under $VERBOSE, .rspec's --require builds RSpec's reporter, and the child's
# later change of its output stream warned, so every isolated verdict was lost.
RSpec.describe(Kimera::Execution) do
  let(:dir) { Dir.mktmpdir }
  let(:lib) { File.expand_path("../../lib", __dir__) }

  after { FileUtils.remove_entry(dir) }

  def project(files)
    files.each do |path, text|
      FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
      File.write(File.join(dir, path), text)
    end
  end

  def child = [RbConfig.ruby, "-rbundler/setup", "-I", lib, File.join(lib, "kimera/execution/isolated_child.rb")]

  def run_child
    File.write(File.join(dir, "request.json"), JSON.generate(tests: ["spec/sum_spec.rb"]))
    env = { "BUNDLE_GEMFILE" => File.expand_path("../../Gemfile", __dir__) }
    output, status = Open3.capture2e(env, *child, "ledger.json", "request.json", chdir: dir)
    [status.success?, output, JSON.parse(File.read(File.join(dir, "ledger.json")))]
  end

  def strict = "module Warning\n  def self.warn(message, **) = raise(message.to_s)\nend\n$VERBOSE = true\n"

  it "has the isolated RSpec child report to its ledger, and print nothing, when the suite raises on warnings" do
    project(
      ".rspec" => "--require spec_helper\n", "spec/spec_helper.rb" => "#{strict}RSpec.configuration.reporter\n",
      "spec/sum_spec.rb" => "RSpec.describe(\"sum\") { it { expect(1 + 1).to(eq(2)) } }\n"
    )
    expect(run_child).to(eq([true, "", { "failures" => 0, "failing" => [] }]))
  end
end
