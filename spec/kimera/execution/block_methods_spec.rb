# frozen_string_literal: true

require "fileutils"
require "kimera/execution/schemata"
require "kimera/registry/builder"
require "tmpdir"

# R4-KL10: dry-types' `RSpec.shared_examples_for … do def be_boolean …`: the
# block defines its method on each example group that includes it, which the
# source cannot name, so the overlay's copy reached none of them and every
# mutant in it read "no test executed this line".
RSpec.describe(Kimera::Execution::BlockMethods) do
  let(:dir) { Dir.mktmpdir }
  let(:file) { File.join(dir, "shared.rb") }

  # A DSL that runs each block it is handed on a class of its own, as
  # RSpec's it_behaves_like does.
  let(:dsl) do
    Module.new do
      def self.made = @_made ||= []
      def self.shared(&) = made << Class.new { class_exec(&) }
    end
  end

  let(:source) do
    <<~RUBY
      module BlockMethodsScope
        LIMIT = 1

        class Empty
        end

        class Host
          BlockMethodsDsl.shared do
            def over(value)
              value > LIMIT
            end

            private def under(value) = value < LIMIT

            def plain = :plain

            def self.made = LIMIT == 1
          end

          BlockMethodsDsl.shared do
            def over(value) = value > 5
          end
        end
      end
    RUBY
  end

  before do
    stub_const("BlockMethodsDsl", dsl)
    stub_const("BlockMethodsScope", Module.new)
    File.write(file, source)
    require(file)
  end

  after do
    $LOADED_FEATURES.delete(file)
    FileUtils.remove_entry(dir)
  end

  def registry = @_registry ||= Kimera::RegistryScan.new(root: dir).build([file])

  def overlay! = Kimera::Execution::Schemata.new(registry, root: dir).overlay!

  def made(index = 0) = BlockMethodsDsl.made.fetch(index)

  def flipped(label, line, &)
    found = registry.each.find { |mutant, point| mutant.label == label && point.location.start_line == line }
    Kimera::RUNTIME.during(found.first.id, &)
  end

  def blocks(woven = source, text = source) = described_class.new(file, text, woven, registry.each.map { _2.location })

  it "defines the woven method on each module the block ran on", :aggregate_failures do
    overlay!
    expect([made.new.over(2), flipped("> => <", 10) { made.new.over(2) }]).to(eq([true, false]))
    expect(made.instance_method(:over).source_location).to(eq([file, 9]))
  end

  it "gives each block's module its own def, by line", :aggregate_failures do
    overlay!
    expect([made(1).new.over(6), flipped("> => <", 21) { made(1).new.over(6) }]).to(eq([true, false]))
    expect(flipped("> => <", 10) { made(1).new.over(6) }).to(be(true))
  end

  it "keeps the method's lexical scope and its visibility", :aggregate_failures do
    overlay!
    expect([made.new.__send__(:under, 0), flipped("< => >", 13) { made.new.__send__(:under, 0) }]).to(eq([true, false]))
    expect(made.private_method_defined?(:under)).to(be(true))
  end

  it "leaves a def with no mutant in it, and one with a receiver, as loaded", :aggregate_failures do
    plain = made.instance_method(:plain)
    singleton = made.singleton_class.instance_method(:made)
    overlay!
    expect(made.instance_method(:plain)).to(eq(plain))
    expect(made.singleton_class.instance_method(:made)).to(eq(singleton))
  end

  it "defines nothing on a subclass of a module the block ran on" do
    heir = Class.new(made)
    overlay!
    expect(heir.instance_method(:over).owner).to(eq(made))
  end

  it "leaves alone a method another file defined" do
    other = File.join(dir, "other.rb")
    File.write(other, "BlockMethodsDsl.made.first.class_eval { def over(_value) = :elsewhere }\n")
    load(other)
    overlay!
    expect(made.new.over(2)).to(eq(:elsewhere))
  end

  it "leaves alone a def it cannot pair with the overlay's" do
    held = made.instance_method(:over)
    blocks(source.sub("def over(value)\n", "def other(value)\n")).adopt { :installed }
    expect(made.instance_method(:over)).to(eq(held))
  end

  it "answers what the overlay answers" do
    expect(blocks.adopt { :installed }).to(eq(:installed))
  end

  def searched(*texts)
    allow(ObjectSpace).to(receive(:each_object).and_call_original)
    texts.each do |text|
      located = Kimera::RegistryScan.new.source(text, file: "x.rb").each.map { _2.location }
      described_class.new(file, text, text, located).adopt { :installed }
    end
    ObjectSpace
  end

  it "searches the heap only for a file with a def inside a block", :aggregate_failures do
    expect(searched("class Host\n  def over(value) = value > 1\nend\n", "Dsl.shared { def self.made = 1 > 0 }\n"))
      .not_to(have_received(:each_object))
    expect(searched(source)).to(have_received(:each_object).with(Module).at_least(:once))
  end
end
