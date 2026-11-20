# frozen_string_literal: true

require "fileutils"
require "kimera/execution/load_trace"
require "kimera/registry/builder"
require "tmpdir"

using PointFields

RSpec.describe(Kimera::Execution::LoadTrace) do
  let(:source) do
    <<~RUBY
      module LoadTraceFees
        def self.charges(base, flag)
          base.define_method(:cost) { flag ? 1 : 2 }
          cache(flag)
        end

        def self.cache(flag)
          @cache ||= (flag == true)
        end

        def self.idle(a, b)
          a > b
        end
      end
    RUBY
  end

  let(:dir) { Dir.mktmpdir }
  let(:file) { File.join(dir, "fees.rb").tap { |path| File.write(path, source) } }
  let(:registry) { Kimera::RegistryScan.new(root: dir).build([file]) }

  def inside
    stub_const("LoadTraceFees", Module.new)
    yield
  ensure
    FileUtils.remove_entry(dir)
  end

  def point(text) = registry.to_a.find { |found| found.original_source == text }

  def macro(trace, path = file)
    trace.record do
      load(path)
      LoadTraceFees.charges(Class.new, true)
    end
  end

  def traced(coverage = {}, root: dir)
    described_class.new(registry, root).tap { |trace| macro(trace) }.quarantine!(coverage)
  end

  it "sends the uncovered mutants of a method that ran while loading to the isolated tier", :aggregate_failures do
    inside do
      traced
      expect(PointVerdict.new(point("flag ? 1 : 2"))).to(have_attributes(safe?: false, hazard: Kimera::Reason::LOAD_REASON))
      expect(point("flag ? 1 : 2").reasons(Kimera::Reason.unreloadable).empty?).to(be(false))
    end
  end

  it "leaves a method that did not run while loading", :aggregate_failures do
    inside do
      traced
      expect(PointVerdict.new(point("a > b"))).to(have_attributes(safe?: true, hazard: nil, revisit: nil))
    end
  end

  it "marks a covered point of a method that ran while loading", :aggregate_failures do
    inside do
      ternary = point("flag ? 1 : 2")
      traced({ ternary.ids.first => ["t1"] })
      expect(PointVerdict.new(ternary)).to(have_attributes(safe?: true, revisit: Kimera::Reason::BOOT_REASON))
    end
  end

  it "leaves a point already sent elsewhere for a reason of its own" do
    inside do
      traced
      expect(point("flag == true").reasons(Kimera::Reason.unsafety).first).not_to(eq(Kimera::Reason::LOAD_REASON))
    end
  end

  it "leaves a point a test covers, by integer or string id", :aggregate_failures do
    inside do
      ternary = point("flag ? 1 : 2")
      coverages = [{ ternary.ids.first => ["t1"] }, { ternary.ids[1].to_s => ["t1"] }]
      expect(coverages.map { |coverage| traced(coverage).then { ternary.safe? } }).to(eq([true, true]))
    end
  end

  it "resolves a relative root against the working directory" do
    inside do
      Dir.chdir(dir) { traced(root: ".") }
      expect(point("flag ? 1 : 2").safe?).to(be(false))
    end
  end

  def symlinked
    real, linked = %w[real linked].map { |name| File.join(dir, name) }
    FileUtils.mkdir_p(real)
    File.write(File.join(real, "fees.rb"), source)
    File.symlink(real, linked)
    Kimera::RegistryScan.new(root: linked).build([File.join(linked, "fees.rb")])
  end

  def relinked(scan)
    trace = described_class.new(scan, File.join(dir, "linked"))
    macro(trace, File.realpath(File.join(dir, "real", "fees.rb")))
    trace.quarantine!({})
  end

  it "recognizes a file loaded through its real path" do
    inside do
      linked = symlinked
      relinked(linked)
      expect(linked.to_a.find { |found| found.original_source == "flag ? 1 : 2" }.safe?).to(be(false))
    end
  end

  it "accepts a registry file that is not on disk" do
    inside do
      sourced = Kimera::RegistryScan.new.source(source, file: "absent.rb")
      expect(described_class.new(sourced, dir).record { :loaded }).to(eq(:loaded))
    end
  end

  def boost = File.write(file, "class LoadTraceBoost\n  belongs_to :booster, default: -> { Current.user }\nend\n")

  it "also quarantines the uncovered lambdas a class-body macro is handed" do
    inside do
      boost
      described_class.new(registry, dir).quarantine!({})
      expect(point("Current.user").reasons(Kimera::Reason.unsafety).first).to(eq(Kimera::Reason::MACRO_REASON))
    end
  end

  it "leaves the lambdas a class-body macro is handed in a file it guarded as it loaded" do
    inside do
      boost.then { stub_const("LoadTraceBoost", Class.new { def self.belongs_to(*, **) = nil }) }
      described_class.new(registry, dir).tap { |trace| trace.record { load(file) } }.quarantine!({})
      expect(point("Current.user").reasons(Kimera::Reason.unsafety)).to(eq([]))
    end
  end

  it "also sends a warm survivor whose mutant leaves its method no yield to a fresh mirror" do
    inside do
      File.write(file, "class LoadTraceJoin\n  def join(list)\n    list.each { |x| yield x }\n  end\nend\n")
      described_class.new(registry, dir).quarantine!({})
      expect(point("list.each { |x| yield x }").reasons(Kimera::Reason.revisiting).first).to(eq(Kimera::Reason::BLOCK_REASON))
    end
  end
end
