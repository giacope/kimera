# frozen_string_literal: true

RSpec.describe("a source file the suite requires lazily") do
  # dry-validation loads its extensions on demand. The overlay evaluated such a
  # file before the suite did, so the suite's own require loaded the original
  # over the guarded methods: the covered mutants read as no_coverage, exit 0.
  def write(fixture, loader)
    FileUtils.mkdir_p(File.join(fixture, "app"))
    FileUtils.mkdir_p(File.join(fixture, "spec"))
    File.write(File.join(fixture, "app", "ext.rb"), "module Ext\n  def self.big?(n)\n    n > 10\n  end\nend\n")
    File.write(File.join(fixture, "spec", "ext_spec.rb"), <<~RUBY)
      RSpec.describe("Ext") do
        it "loads on demand" do
          #{loader}
          expect(Ext.big?(11)).to be(true)
          expect(Ext.big?(10)).to be(false)
        end
      end
    RUBY
  end

  def judged(loader)
    Dir.mktmpdir("kimera-lazy") do |fixture|
      write(fixture, loader)
      test_run(cwd: fixture) { |_output, report, _status| return report["results"].map { |r| r["status"] }.tally }
    end
  end

  it "keeps its mutants live across a later require_relative" do
    expect(judged('require_relative "../app/ext"')).to(eq("killed" => 2))
  end

  it "keeps its mutants live across a later require through $LOAD_PATH" do
    expect(judged('$LOAD_PATH.unshift(File.expand_path("../app", __dir__)); require "ext"')).to(eq("killed" => 2))
  end
end
