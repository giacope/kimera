# frozen_string_literal: true

require "fileutils"
require "kimera/execution/schemata"
require "kimera/registry/builder"
require "tmpdir"

# K3-7: the overlay evaluated a generator template nothing loads, which
# reassigned the suite's own settings inside the test process.
RSpec.describe(Kimera::Execution::Schemata, :aggregate_failures) do
  let(:dir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(dir)
  end

  def write(relative, body)
    File.write(File.join(dir, relative), body)
    File.join(dir, relative)
  end

  def overlaid(loaded)
    files = [
      write("reach_template.rb", "ReachSettings[:greet] = -> { 1 > 0 ? \"from the template\" : \"\" }\n"),
      write("reach_defined.rb", "class ReachDefined\n  def big?(n) = n > 1\nend\n")
    ]
    registry = Kimera::RegistryScan.new(root: dir).build(files)
    live = described_class.new(registry, root: dir, loaded: loaded).overlay!
    [registry, live]
  end

  before do
    stub_const("ReachSettings", {})
    stub_const("ReachDefined", Class.new)
  end

  def point(registry, file) = registry.points.find { |found| found.file == file }

  it "never evaluates a file the suite did not load when its top level runs code" do
    registry, live = overlaid(proc { false })
    template = point(registry, "reach_template.rb")
    expect(ReachSettings).to(be_empty)
    expect(template.unloaded?).to(be(true))
    expect(live & template.ids).to(be_empty)
  end

  it "still evaluates such a file the suite did load", :aggregate_failures do
    registry, live = overlaid(proc { true })
    expect(live).to(include(*point(registry, "reach_template.rb").ids))
    expect(point(registry, "reach_template.rb").unloaded?).to(be(false))
  end

  # A registry of the one file, overlaid as if the suite had loaded nothing.
  def unasked(name, body)
    path = write(name, body)
    registry = Kimera::RegistryScan.new(root: dir).build([path])
    [registry, described_class.new(registry, root: dir, loaded: proc { false })]
  end

  # R5-KL4: slim's include.rb (`after Parser, Include` in its class body) ran in every worker.
  it "never evaluates a file the suite did not load when a class body in it runs code", :aggregate_failures do
    stub_const("ReachCore", Module.new)
    registry, loader = unasked("reach_plugin.rb", "module ReachCore\n  @limit = 100\n  def self.big?(n) = n > 1\nend\n")
    loader.overlay!
    expect(ReachCore.instance_variable_get(:@limit)).to(be_nil)
    expect(point(registry, "reach_plugin.rb").unloaded?).to(be(true))
  end

  # R5-KL4: i18n's key_value.rb needs a gem the suite never loads: 45 mutants were unmutatable, unscored.
  it "reports a file the suite did not load, and kimera could not, uncovered with the error", :aggregate_failures do
    source = "require \"reach_no_such_gem\"\nmodule ReachOptional\n  def self.big?(n) = n > 1\nend\n"
    registry, loader = unasked("reach_optional.rb", source)
    expect { loader.overlay! }.not_to(output.to_stderr)
    failed = "(nor could kimera load it: LoadError: cannot load such file -- reach_no_such_gem)"
    expect(point(registry, "reach_optional.rb").unsafe_reason).to(eq("#{Kimera::MutationPoint::NEVER} #{failed}"))
  end

  # R5-KL5: kramdown's parser registry (`@@parsers = {}` in an autoloaded class body) was emptied.
  it "loads an autoloaded file as the suite would, then trims it, so its class body runs once", :aggregate_failures do
    stub_const("ReachReg", Module.new)
    ReachReg.autoload(:Table, File.join(dir, "reach_table.rb"))
    registry, loader = unasked("reach_table.rb", <<~RUBY)
      module ReachReg
        class Table
          @@rows = ROWS = {}
          def self.big?(n) = n > 10
        end
      end
      ReachReg::Table::ROWS[:a] = 1
    RUBY
    expect([loader.overlay!, ReachReg::Table.class_variable_get(:@@rows)])
      .to(match([include(*point(registry, "reach_table.rb").ids), { a: 1 }]))
  end

  it "still evaluates a definitions-only file the suite did not load", :aggregate_failures do
    registry, live = overlaid(proc { |path| path != "reach_defined.rb" })
    expect(live).to(include(*point(registry, "reach_defined.rb").ids))
    expect(point(registry, "reach_defined.rb").unloaded?).to(be(false))
  end
end
