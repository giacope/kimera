# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# R3K5: code .rspec's --require loaded ran before kimera's load trace began.
# R3K2: a lambda a class body calls ran while loading, not as a method.
# K3-7: an in-scope file the suite never loads was evaluated anyway.
RSpec.describe("kimera run on code that runs while the suite loads (end-to-end)", :aggregate_failures) do
  def project(root, files)
    files.each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), body)
    end
  end

  def files = {
    ".rspec" => "--require spec_helper\n",
    "spec/spec_helper.rb" =>
      "require_relative \"../app/flags\"\nrequire_relative \"../app/limits\"\nSETTINGS = { greet: \"hello\" }\n",
    "app/flags.rb" => <<~RUBY,
      class Flags
        def self.flag(key)
          define_method(:"\#{key}?") { (@set ||= {})[key] == true }
          define_method(:"\#{key}!") { (@set ||= {})[key] = true }
        end
        private_class_method :flag

        flag :strict
      end
    RUBY
    "app/limits.rb" => <<~RUBY,
      class Limits
        env_int = lambda do |val|
          val if val >= 0
        end
        MAX = env_int.call(4096)
      end
    RUBY
    "app/setup.rb" => "SETTINGS[:greet] = -> { 1 > 0 ? \"hi from a file nothing loads\" : \"\" }\n",
    "spec/flags_spec.rb" => <<~RUBY
      RSpec.describe(Flags) do
        it("is unset") { expect(Flags.new.strict?).to be(false) }
        it("is set") { expect(Flags.new.tap(&:strict!).strict?).to be(true) }
        it("caps") { expect(Limits::MAX).to eq(4096) }
        it("greets") { expect(SETTINGS[:greet]).to eq("hello") }
      end
    RUBY
  }

  def statuses(report, file) = report["results"].select { |r| r["file"] == file }.map { |r| r["status"] }.uniq

  it "judges load-time code in the isolated tier and never evaluates a file nothing loads" do
    Dir.mktmpdir("kimera-load") do |root|
      project(root, files)
      test_run(cwd: root) do |output, report, status|
        expect(report).not_to(be_nil, "no JSON report; output:\n#{output}")
        expect(statuses(report, "app/flags.rb")).to(eq(["isolated_only"]))
        expect(statuses(report, "app/limits.rb")).to(eq(["isolated_only"]))
        setup = report["results"].select { |r| r["file"] == "app/setup.rb" }
        expect(setup.map { |r| r["status"] }.uniq).to(eq(["no_coverage"]))
        expect(setup.map { |r| r["detail"] }.uniq).to(eq([Kimera::MutationPoint::NEVER_LOADED]))
        expect(status).to(eq(2))
      end
    end
  end

  it "kills the load-time mutants a test can see when judged in mirrors" do
    Dir.mktmpdir("kimera-load") do |root|
      project(root, files)
      test_run(cwd: root, arguments: ["--isolated", "--exclude", "app/setup.rb"]) do |output, report, _status|
        expect(report).not_to(be_nil, "no JSON report; output:\n#{output}")
        flags = report["results"].select { |r| r["file"] == "app/flags.rb" }
        expect(flags.map { |r| r["status"] }).to(include("killed"))
        expect(report["counts"]["no_coverage"]).to(eq(0))
      end
    end
  end
end
