# frozen_string_literal: true

require "fileutils"
require "kimera/execution/block_use"
require "kimera/registry/builder"
require "tmpdir"

# R6B2-M3: Ruby settles whether a method uses the block passed to it as it
# compiles the method, and the warm overlay compiles every mutant of a method
# into one. A mutant that leaves the method no `yield` warns, under a suite that
# reports ignored blocks, only when baked alone: warm it survived (dry-monads'
# `Right#and`, `if block_given?` => `if false`).
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
    scan.points.select(&:revisit).map { |point| [point.location.start_line, point.operator] }
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
    expect(registry.points.filter_map(&:revisit).uniq).to(eq([described_class::REASON]))
  end

  it "judges them warm when the suite reports no ignored block", :aggregate_failures do
    expect(warnings(strict: false, verbose: false) { revisited(scanned(source, "quiet.rb")) }).to(eq([]))
    expect(warnings(strict: true, verbose: nil) { revisited(scanned(source, "silent.rb")) }).to(eq([]))
    expect(warnings(strict: false, verbose: true) { revisited(scanned(source, "loud.rb")) }.size).to(eq(3))
  end

  it "leaves a point sent elsewhere already, for a reason or a revisit of its own", :aggregate_failures do
    first, second = registry.points.select { |point| point.location.start_line == 12 }
    first.unsafe!(Kimera::MutationPoint::LOAD_REASON)
    second.revisit!(Kimera::MutationPoint::BOOT_REASON)
    expect(revisited).to(eq([[3, "conditional"], [12, "conditional"]]))
    expect(second.revisit).to(eq(Kimera::MutationPoint::BOOT_REASON))
  end

  def dropped(body) = revisited(scanned("class BlockUseOne\n#{body}\nend\n", "one.rb"))

  def guarded(line) = dropped("  def a(list)\n    #{line}\n    list.each { |x| yield x }\n  end")

  it "counts a yield in a nested def as that def's, and a zsuper without a block as a use", :aggregate_failures do
    expect(guarded("def b = yield")).to(eq([[4, "statement_deletion"]]))
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

  # Ruby leaves out a branch its condition rules out as it compiles: `if false`,
  # `if nil`, and the else of `if 1`, `if "s"`, `if :a`, `if -> {}`.
  it "counts no yield in a branch a literal condition rules out" do
    dead = %w[false nil (false) (1;nil) true&&false @x&&nil false||nil].map { |literal| guarded("yield if #{literal}") }
    expect(dead.uniq).to(eq([[[4, "statement_deletion"]]]))
  end

  it "counts no yield in the else of a truthy literal condition" do
    truthy = ["true", "1", "1.5", "1r", "1i", '"s"', ":a", "->{}", "__LINE__", "@x||true", "yield unless true"]
    expect(truthy.map { |literal| guarded(literal.start_with?("yield") ? literal : "#{literal} ? 1 : yield") }.uniq).to(
      eq([[[4, "statement_deletion"]]])
    )
  end

  it "counts the yield of a branch a condition may take" do
    live = %w[@x !false @x&&true true&&@x false||@x /x/ []].map { |literal| guarded("#{literal} ? 1 : yield") }
    expect(live.uniq).to(eq([[]]))
  end
end
