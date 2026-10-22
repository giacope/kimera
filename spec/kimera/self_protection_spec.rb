# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/self_protection"
require "tmpdir"

RSpec.describe(Kimera::SelfProtection) do
  def protected?(path) = described_class.new(path).protected?

  def critical?(path) = described_class.new(path).critical?

  describe "#own?" do
    it "knows kimera's own source, through a relative path, and nothing else", :aggregate_failures do
      expect(described_class.new(Kimera::Runtime::SOURCE_PATH).own?).to(be(true))
      Dir.chdir(File.dirname(Kimera::Runtime::SOURCE_PATH)) { expect(described_class.new("cli.rb").own?).to(be(true)) }
      expect(described_class.new("app/models/user.rb").own?).to(be(false))
      expect(described_class.new("#{File.dirname(Kimera::Runtime::SOURCE_PATH)}x/a.rb").own?).to(be(false))
      expect(described_class.new(__FILE__).own?).to(be(false))
    end
  end

  describe "#protected?" do
    it "protects the runtime selector's own source file" do
      expect(protected?(Kimera::Runtime::SOURCE_PATH)).to(be(true))
    end

    it "protects child-process entrypoints that execute immediately when loaded" do
      expect(described_class::OUT_OF_PROCESS_ENTRYPOINTS).to(all(satisfy { |path| protected?(path) }))
    end

    it "resolves relative paths before matching" do
      Dir.chdir(File.dirname(Kimera::Runtime::SOURCE_PATH)) do
        expect(protected?("runtime.rb")).to(be(true))
      end
    end

    it "does not protect ordinary application files", :aggregate_failures do
      expect(protected?("app/models/user.rb")).to(be(false))
      expect(protected?(__FILE__)).to(be(false))
    end

    it "protects the selector reached through a symlink" do
      Dir.mktmpdir do |dir|
        link = File.join(dir, "linked_runtime.rb")
        File.symlink(Kimera::Runtime::SOURCE_PATH, link)
        expect(protected?(link)).to(be(true))
      end
    end
  end

  describe "#canonical" do
    it "falls back to expand_path when realpath cannot resolve the path" do
      canonical = described_class.new(nil).__send__(:canonical, "no/such/dir/../file.rb")
      expect(canonical).to(eq(File.expand_path("no/such/file.rb")))
    end
  end

  describe "#critical?" do
    def fixtures
      %w[
        lib/kimera/frameworks/rspec_suite.rb
        lib/kimera/frameworks/minitest_suite.rb
        lib/kimera/frameworks/suite.rb
        lib/kimera/exits/test_exit.rb
        lib/kimera/execution/shift.rb
        lib/kimera/execution/harness.rb
        lib/kimera/execution/stopwatch.rb
        lib/kimera/execution/time_budget.rb
        lib/kimera/execution/worker_pool.rb
        lib/kimera/execution/worker_pool/fleet.rb
        lib/kimera/execution/child_process.rb
        lib/kimera/execution/rig.rb
        lib/kimera/registry/builder.rb
      ]
    end

    it "flags Kimera's own in-process runner files" do
      fixtures.each { |f| expect(critical?(f)).to(be(true)) }
    end

    it "does not flag ordinary application files (even same-named ones)", :aggregate_failures do
      expect(critical?("app/jobs/worker.rb")).to(be(false))
      expect(critical?("lib/execution/harness.rb")).to(be(false))
      expect(critical?(nil)).to(be(false))
    end
  end

  describe "integration with the registry builder" do
    it "builds no mutation points for the runtime selector" do
      registry = Kimera::RegistryScan.new(root: ".").build([Kimera::Runtime::SOURCE_PATH])
      expect(registry.count).to(eq(0))
    end

    it "builds no warm mutation points for the Minitest child entrypoint" do
      child = described_class::OUT_OF_PROCESS_ENTRYPOINTS.find { |path| path.end_with?("isolated_child_minitest.rb") }
      registry = Kimera::RegistryScan.new(root: ".").build([child])
      expect(registry.count).to(eq(0))
    end

    # An instrumented runtime.rb makes Runtime.active? recurse into itself.
    it "keeps the runtime out of a whole-lib registry" do
      lib = File.expand_path("../../lib", __dir__)
      registry = Kimera::RegistryScan.new(root: lib).build(Dir["#{lib}/**/*.rb"])
      expect(registry.files).not_to(include(a_string_matching(/runtime\.rb\z/)))
    end

    # The isolated oracle bakes mutants into source, so it has no selector to recurse through.
    it "includes the runtime when shielding is disabled" do
      registry = Kimera::RegistryScan.new(root: ".", shielded: false).build([Kimera::Runtime::SOURCE_PATH])
      expect(registry.count).to(be > 0)
    end

    it "includes the Minitest child entrypoint when shielding is disabled" do
      child = described_class::OUT_OF_PROCESS_ENTRYPOINTS.find { |path| path.end_with?("isolated_child_minitest.rb") }
      registry = Kimera::RegistryScan.new(root: ".", shielded: false).build([child])
      expect(registry.count).to(be > 0)
    end
  end
end
