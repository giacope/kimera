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
    Kimera::RUNTIME.reset!
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

  it "still evaluates such a file the suite did load, and a definitions-only file it did not" do
    registry, live = overlaid(proc { true })
    expect(live).to(include(*point(registry, "reach_template.rb").ids))
    expect(point(registry, "reach_template.rb").unloaded?).to(be(false))
    Kimera::RUNTIME.reset!
    registry, live = overlaid(proc { |path| path != "reach_defined.rb" })
    expect(live).to(include(*point(registry, "reach_defined.rb").ids))
    expect(point(registry, "reach_defined.rb").unloaded?).to(be(false))
  end
end
