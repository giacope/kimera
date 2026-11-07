# frozen_string_literal: true

require "fileutils"
require "kimera/execution/block_use"
require "kimera/registry/builder"
require "tmpdir"

using PointFields

RSpec.describe(Kimera::Execution::BlockUse) do
  let(:source) do
    <<~RUBY
      class BlockUsePair
        def join
          if block_given?
            yield([@left, @right])
          else
            [@left, @right]
          end
        end

        def each_positive(list)
          return to_enum(:each_positive, list) unless block_given?
          list.each { |item| yield item if item > 0 }
        end

        def twice
          yield
          yield if @again
        end

        def given(&block) = block ? block.call : nil

        define_method(:above) { |v| v > 1 }

        def tally(list)
          list.map { |item| item > 1 }
          yield 2
        end
      end
    RUBY
  end

  let(:dir) { Dir.mktmpdir }
  let(:registry) { scanned(source) }

  after { FileUtils.remove_entry(dir) }

  def scanned(text, name = "pair.rb")
    Kimera::RegistryScan.new(root: dir).build([File.join(dir, name).tap { |path| File.write(path, text) }])
  end

  def revisited(scan = registry)
    described_class.new(scan, dir).revisit!
    scan.to_a.select { PointVerdict.new(it).revisit }.map { |point| [point.location.range.begin, point.operator] }
  end

  def warnings(strict:, verbose:)
    before = [Warning[:strict_unused_block], $VERBOSE]
    Warning[:strict_unused_block] = strict
    $VERBOSE = verbose
    yield
  ensure
    Warning[:strict_unused_block], $VERBOSE = before
  end

  it "sends a warm survivor whose mutant leaves its method no yield to a fresh mirror", :aggregate_failures do
    expect(revisited).to(eq([[3, "conditional"], [12, "statement_deletion"], [12, "conditional"]]))
    expect(registry.to_a.filter_map { PointVerdict.new(it).revisit }.uniq).to(eq([Kimera::Reason::BLOCK_REASON]))
  end

  it "judges them warm when the suite reports no ignored block", :aggregate_failures do
    expect(warnings(strict: false, verbose: false) { revisited(scanned(source, "quiet.rb")) }).to(eq([]))
    expect(warnings(strict: true, verbose: nil) { revisited(scanned(source, "silent.rb")) }).to(eq([]))
    expect(warnings(strict: false, verbose: true) { revisited(scanned(source, "loud.rb")) }.size).to(eq(3))
  end

  it "leaves a point sent elsewhere already, for a reason or a revisit of its own", :aggregate_failures do
    first, second = registry.to_a.select { |point| point.location.range.begin == 12 }
    first.mark!(Kimera::Reason.unsafe(Kimera::Reason::LOAD_REASON))
    second.mark!(Kimera::Reason.revisit(Kimera::Reason::BOOT_REASON))
    expect(revisited).to(eq([[3, "conditional"], [12, "conditional"]]))
    expect(second.reasons(Kimera::Reason.revisiting).first).to(eq(Kimera::Reason::BOOT_REASON))
  end

  def dropped(body) = revisited(scanned("class BlockUseOne\n#{body}\nend\n", "one.rb"))

  def guarded(line) = dropped("  def a(list)\n    #{line}\n    list.each { |x| yield x }\n  end")

  it "counts a yield in a nested def as that def's, and a zsuper without a block as a use", :aggregate_failures do
    expect(guarded("def b = yield")).to(eq([[4, "statement_deletion"]]))
    expect(guarded("def b(v) = v > 1 ? yield(v) : v")).to(eq([[3, "conditional"], [4, "statement_deletion"]]))
    expect(guarded("super")).to(eq([]))
    expect(guarded("super { 1 }")).to(eq([[4, "statement_deletion"]]))
  end

  it "takes a block parameter or ... as using the block, whatever the body does", :aggregate_failures do
    expect(dropped("  def a(list, &)\n    list.each { |x| yield x }\n  end")).to(eq([]))
    expect(dropped("  def a(list, ...)\n    list.each { |x| yield x }\n  end")).to(eq([]))
  end

  it "holds a mutant in an endless def to that def" do
    expect(dropped("  def a(v) = v > 1 ? yield(v) : v")).to(eq([[2, "conditional"]]))
  end

  it "counts no yield in a branch a literal condition rules out" do
    dead = %w[false nil (false) (1;nil) true&&false @x&&nil false||nil].map { |literal| guarded("yield if #{literal}") }
    expect(dead.uniq).to(eq([[[4, "statement_deletion"]]]))
  end

  it "counts no yield in the else of a truthy literal condition" do
    truthy = ["true", "1", "1.5", "1r", "1i", '"s"', ":a", "->{}", "__LINE__", "@x||true", "true&&1"]
    expect([*truthy.map { |literal| guarded("#{literal} ? 1 : yield") }, guarded("yield unless true")].uniq).to(
      eq([[[4, "statement_deletion"]]])
    )
  end

  it "counts the yield of the branch a literal condition takes", :aggregate_failures do
    expect(%w[true 1 :a].map { |literal| guarded("yield if #{literal}") }.uniq).to(eq([[]]))
    expect([guarded("false ? 1 : yield"), guarded("nil ? 1 : yield"), guarded("yield unless false")].uniq).to(eq([[]]))
  end

  def either(literal) = [guarded("#{literal} ? 1 : yield"), guarded("yield if #{literal}")]

  it "counts the yield of either branch a condition may take" do
    expect(%w[@x !false @x&&true true&&@x false||@x @x||false /x/ [] ()].flat_map { either(it) }.uniq).to(eq([[]]))
  end

  it "counts what defined? evaluates or checks for a block, not a super it only looks up", :aggregate_failures do
    looked = [
      "defined?(super)", "defined?(super())", "defined?(x(super))", "defined?(super(yield))",
      "defined?((yield; 1))", "defined?(@a = yield)", "defined?(super && 1)"
    ]
    used = [
      "defined?(yield)", "defined?(super.x)", "defined?(yield.x)", "defined?(foo(yield))", "defined?([yield])",
      "defined?(super[1])", "defined?((yield))"
    ]
    expect(looked.map { guarded(it) }.uniq).to(eq([[[4, "statement_deletion"]]]))
    expect(used.map { guarded(it) }.uniq).to(eq([[]]))
  end

  it "judges again the mutant that drops the only super a defined?(super) guards" do
    code = "class BlockUseAudit < Object\n  def notify(event)\n    return super if defined?(super)\n    " \
      "nil\n  end\nend\n"
    scan = Kimera::RegistryScan.new(root: dir, operators: Kimera::Operators.build(keys: %w[super_call]))
    points = revisited(scan.build([File.join(dir, "audit.rb").tap { |path| File.write(path, code) }]))
    expect(points).to(eq([[3, "super_call"]]))
  end

  it "takes a mutant it cannot apply as leaving the method no yield" do
    join = registry.to_a.find { |point| point.location.range.begin == 3 }
    odd = join.to_h.merge("mutants" => [{ "id" => 1, "label" => "odd", "directive" => { "type" => "odd" } }])
    tree = Kimera::Execution::BlockUse::Source.new(Kimera::Syntax.parse(source).value)
    expect(tree.drops?(Kimera::MutationPoint.from_h(odd))).to(be(true))
  end

  it "leaves alone a point whose node the tree no longer holds" do
    join = registry.to_a.find { |point| point.location.range.begin == 3 }
    odd = join.to_h.merge("mutants" => [{ "id" => 1, "label" => "odd", "directive" => { "type" => "odd" } }])
    tree = Kimera::Execution::BlockUse::Source.new(Kimera::Syntax.parse("x = 1\n").value)
    expect(tree.drops?(Kimera::MutationPoint.from_h(odd))).to(be(false))
  end
end
