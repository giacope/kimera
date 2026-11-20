# frozen_string_literal: true

require "fileutils"
require "kimera/execution/schemata"
require "kimera/registry/builder"
require "tmpdir"

using PointFields

RSpec.describe(Kimera::Execution::Schemata, :aggregate_failures) do
  let(:dir) { Dir.mktmpdir }

  def inside
    stub_const("ReachSettings", {})
    stub_const("ReachDefined", Class.new)
    yield
  ensure
    FileUtils.remove_entry(dir)
  end

  def write(relative, body)
    File.write(File.join(dir, relative), body)
    File.join(dir, relative)
  end

  def booted(loaded)
    Struct.new(:loaded) do
      def loaded?(_file) = loaded.call

      def woven(_file) = yield
    end.new(loaded)
  end

  def overlaid(loaded)
    files = [
      write("reach_template.rb", "ReachSettings[:greet] = -> { 1 > 0 ? \"from the template\" : \"\" }\n"),
      write("reach_defined.rb", "class ReachDefined\n  def big?(n) = n > 1\nend\n")
    ]
    registry = Kimera::RegistryScan.new(root: dir).build(files)
    live = described_class.new(registry, root: dir, trace: booted(loaded)).overlay!
    [registry, live]
  end

  def point(registry, file) = registry.to_a.find { |found| found.file == file }

  it "never evaluates a file the suite did not load when its top level runs code" do
    inside do
      registry, live = overlaid(proc { false })
      template = point(registry, "reach_template.rb")
      expect([ReachSettings, template.reasons(Kimera::Reason.unloaded).any?, live & template.ids])
        .to(eq([{}, true, []]))
    end
  end

  it "still evaluates such a file the suite did load", :aggregate_failures do
    inside do
      registry, live = overlaid(proc { true })
      expect(live).to(include(*point(registry, "reach_template.rb").ids))
      expect(point(registry, "reach_template.rb").reasons(Kimera::Reason.unloaded).any?).to(be(false))
    end
  end

  def unasked(name, body)
    path = write(name, body)
    registry = Kimera::RegistryScan.new(root: dir).build([path])
    [registry, described_class.new(registry, root: dir, trace: booted(proc { false }))]
  end

  def reason(registry, file) = PointVerdict.new(point(registry, file)).hazard

  def hooked
    stub_const("ReachCore", Module.new) && stub_const("ReachRan", [])
    unasked("reach_hook.rb", "module ReachCore\n  ReachRan << 1\n  def self.big?(n) = n > 1\nend\n")
      .tap { |_, loader| loader.overlay! }
  end

  it "never evaluates a file the suite did not load when a class body in it runs code", :aggregate_failures do
    inside do
      registry, = hooked
      expect(ReachRan).to(be_empty)
      expect(reason(registry, "reach_hook.rb")).to(eq(Kimera::Reason::NEVER_LOADED))
    end
  end

  def optional
    source = "require \"reach_no_such_gem\"\nmodule ReachOptional\n  def self.big?(n) = n > 1\nend\n"
    unasked("reach_optional.rb", source)
  end

  def missing = "(nor could kimera load it: LoadError: cannot load such file -- reach_no_such_gem)"

  it "reports a file the suite did not load, and kimera could not, uncovered with the error", :aggregate_failures do
    inside do
      registry, loader = optional
      expect { loader.overlay! }.not_to(output.to_stderr)
      expect(reason(registry, "reach_optional.rb")).to(eq("#{Kimera::Reason::NEVER} #{missing}"))
    end
  end

  def broken
    stub_const("ReachLazy", Module.new).autoload(:Broken, write("reach_broken.rb", "raise \"broken on load\"\n"))
    "module ReachLazy\n  class Broken\n    def self.big?(n) = n > 1\n  end\nend\nReachLazy::Broken.big?(1)\n"
  end

  it "reports a file whose autoload raises, uncovered with the error" do
    inside do
      registry, = unasked("reach_lazy.rb", broken).tap { |_, loader| loader.overlay! }
      expect(reason(registry, "reach_lazy.rb"))
        .to(eq("#{Kimera::Reason::NEVER} (nor could kimera load it: RuntimeError: broken on load)"))
    end
  end

  def table
    stub_const("ReachReg", Module.new)
    ReachReg.autoload(:Table, File.join(dir, "reach_table.rb"))
    unasked("reach_table.rb", <<~RUBY)
      module ReachReg
        class Table
          @@rows = ROWS = {}
          def self.big?(n) = n > 10
        end
      end
      ReachReg::Table::ROWS[:a] = 1
    RUBY
  end

  it "loads an autoloaded file as the suite would, then trims it, so its class body runs once", :aggregate_failures do
    inside do
      registry, loader = table
      expect([loader.overlay!, ReachReg::Table.class_variable_get(:@@rows)])
        .to(match([include(*point(registry, "reach_table.rb").ids), { a: 1 }]))
    end
  end

  def chained
    stub_const("ReachChain", Module.new)
    ReachChain.autoload(:Table, write("reach_table.rb", <<~RUBY))
      module ReachChain
        class Table
          ROWS = {}
          def self.define(name) = ROWS[name] = ROWS.fetch(name, 0) + 1
        end
      end
      require_relative "reach_rows"
    RUBY
    unasked("reach_rows.rb", <<~RUBY)
      module ReachChain
        class Table
          define(:b)
          def self.small?(n) = n < 3
        end
      end
    RUBY
  end

  it "evaluates, trimmed, a file the suite loads through an autoload of a constant it opens" do
    inside do
      registry, loader = chained
      rows = point(registry, "reach_rows.rb").ids
      expect([loader.overlay!, ReachChain::Table::ROWS]).to(match([include(*rows), { b: 1 }]))
    end
  end

  def stray
    stub_const("ReachBase", Class.new)
    stub_const("ReachKid", Class.new(ReachBase))
    ReachBase.autoload(:Stray, write("reach_stray.rb", "ReachSettings[:stray] = true\nclass ReachBase::Stray; end\n"))
    source = "class ReachKid\n  @limit = 1\n  class Stray\n    def self.big?(n) = n > 1\n  end\nend\n"
    unasked("reach_kid.rb", source).last
  end

  it "fires no autoload an ancestor holds for a constant of the same name" do
    inside do
      stray.overlay!
      expect(ReachSettings).not_to(have_key(:stray))
    end
  end

  def linked = File.join(dir, "linked").tap { |link| File.symlink(dir, link) }

  it "knows such a file loaded by its real path too", :aggregate_failures do
    inside do
      registry, = chained
      expect(described_class.new(registry, root: linked, trace: booted(proc { false })).overlay!).not_to(be_empty)
      expect(point(registry, "reach_rows.rb").reasons(Kimera::Reason.unloaded).any?).to(be(false))
    end
  end

  it "still evaluates a definitions-only file the suite did not load", :aggregate_failures do
    inside do
      registry, live = overlaid(proc { |path| path != "reach_defined.rb" })
      expect(live).to(include(*point(registry, "reach_defined.rb").ids))
      expect(point(registry, "reach_defined.rb").reasons(Kimera::Reason.unloaded).any?).to(be(false))
    end
  end
end
