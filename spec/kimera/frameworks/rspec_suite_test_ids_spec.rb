# frozen_string_literal: true

require "fileutils"
require "kimera/frameworks/rspec_suite"
require "tmpdir"

RSpec.describe(Kimera::Frameworks::RSpecSuite, "#test_ids") do
  let(:dir) { Dir.mktmpdir }

  around do |example|
    config = RSpec.configuration
    world = RSpec.world
    groups = world.example_groups.dup
    manager = config.filter_manager
    fallback = config.run_all_when_everything_filtered?
    config.instance_variable_set(:@filter_manager, RSpec::Core::FilterManager.new)
    example.run
  ensure
    world.example_groups.replace(groups)
    config.instance_variable_set(:@filter_manager, manager)
    config.run_all_when_everything_filtered = fallback
    world.filtered_examples.clear
    FileUtils.remove_entry(dir)
  end

  def fixture(focus: false)
    path = File.join(dir, "filtered_spec.rb")
    File.write(path, <<~RUBY)
      RSpec.describe "KimeraFiltered" do
        it("passes") { expect(1).to eq(1) }
        it("fails"#{", focus: true" if focus}) { expect(1).to eq(2) }
      end
    RUBY
    path
  end

  def filtered(fallback:, focus: false)
    RSpec.configuration.filter_run_including(focus: true)
    RSpec.configuration.run_all_when_everything_filtered = fallback
    adapter = described_class.new.source([fixture(focus: focus)])
    [adapter, adapter.test_ids.select { |id| adapter[id].name.start_with?("KimeraFiltered") }]
  end

  it "selects every example when the focus filter matches none and the suite asks for that" do
    adapter, ids = filtered(fallback: true)
    expect(ids.map { |id| adapter[id].name }).to(eq(["KimeraFiltered passes", "KimeraFiltered fails"]))
  end

  it "runs an example the fallback selected" do
    adapter, ids = filtered(fallback: true)
    expect(adapter.run([ids.last]).to_h.fetch("failed_ids")).to(eq([ids.last]))
  end

  it "keeps only the focused examples when the filter matches some" do
    adapter, ids = filtered(fallback: true, focus: true)
    expect(ids.map { |id| adapter[id].name }).to(eq(["KimeraFiltered fails"]))
  end

  it "selects nothing when the filter matches none and the suite does not ask for the fallback" do
    expect(filtered(fallback: false).last).to(eq([]))
  end

  def unfocused
    RSpec.configuration.filter_run_including(focus: true)
    RSpec.configuration.run_all_when_everything_filtered = true
    Kernel.load(fixture)
    RSpec.world.example_groups.each { |group| RSpec.world.filtered_examples[group] }
    described_class.new.source([])
  end

  it "forgets the examples the filter had selected before it fell back" do
    adapter = unfocused
    failing = adapter.test_ids.find { |id| adapter[id].name == "KimeraFiltered fails" }
    expect(adapter.run([failing]).to_h.fetch("failed_ids")).to(eq([failing]))
  end

  it "selects nothing, and stops, when there is no example and no filter" do
    RSpec.world.example_groups.clear
    RSpec.configuration.run_all_when_everything_filtered = true
    expect(described_class.new.source([]).test_ids).to(eq([]))
  end
end
