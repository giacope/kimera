# frozen_string_literal: true

require "fileutils"
require "kimera/execution/load_trace"
require "kimera/registry/builder"
require "tmpdir"

RSpec.describe(Kimera::Execution::LoadTrace) do
  # A macro a class body calls while it loads, a method it never calls, and a
  # memoized (schema-unsafe) method the macro calls too.
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

  before { stub_const("LoadTraceFees", Module.new) }

  after { FileUtils.remove_entry(dir) }

  def point(text) = registry.points.find { |found| found.original_source == text }

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
    traced
    expect(point("flag ? 1 : 2")).to(have_attributes(safe?: false, unsafe_reason: Kimera::MutationPoint::LOAD_REASON))
    expect(point("flag ? 1 : 2").reloadable?).to(be(false))
  end

  it "leaves a method that did not run while loading", :aggregate_failures do
    traced
    expect(point("a > b")).to(have_attributes(safe?: true, unsafe_reason: nil))
  end

  it "leaves a point already sent elsewhere for a reason of its own" do
    traced
    expect(point("flag == true").unsafe_reason).not_to(eq(Kimera::MutationPoint::LOAD_REASON))
  end

  it "leaves a point a test covers, by integer or string id", :aggregate_failures do
    ternary = point("flag ? 1 : 2")
    first, *rest = ternary.ids
    traced({ first => ["t1"] })
    expect(ternary.safe?).to(be(true))
    traced({ rest.first.to_s => ["t1"] })
    expect(ternary.safe?).to(be(true))
  end

  it "resolves a relative root against the working directory" do
    Dir.chdir(dir) { traced(root: ".") }
    expect(point("flag ? 1 : 2").safe?).to(be(false))
  end

  it "recognizes a file loaded through its real path" do
    FileUtils.mkdir_p(File.join(dir, "real"))
    File.write(File.join(dir, "real", "fees.rb"), source)
    File.symlink(File.join(dir, "real"), File.join(dir, "linked"))
    linked = Kimera::RegistryScan.new(root: File.join(dir, "linked")).build([File.join(dir, "linked", "fees.rb")])
    trace = described_class.new(linked, File.join(dir, "linked"))
    macro(trace, File.realpath(File.join(dir, "real", "fees.rb")))
    trace.quarantine!({})
    expect(linked.points.find { |found| found.original_source == "flag ? 1 : 2" }.safe?).to(be(false))
  end

  it "accepts a registry file that is not on disk" do
    sourced = Kimera::RegistryScan.new.source(source, file: "absent.rb")
    expect(described_class.new(sourced, dir).record { :loaded }).to(eq(:loaded))
  end
end
