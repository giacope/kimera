# frozen_string_literal: true

# R6B2-M1: dry-rb's spec_helper turns on Warning[:strict_unused_block] and raises
# every warning. kimera's own calls passed blocks to methods that ignore them, so
# the first memoized mutant ended the run and the first warm kill of each worker
# read `error`.
RSpec.describe("a suite that raises every warning, unused blocks included") do
  def files = {
    "app/totals.rb" => <<~RUBY,
      # frozen_string_literal: true
      class Totals
        def initialize(items)
          @items = items
        end

        def sum
          @sum ||= @items.sum { |item| item > 0 ? item : 0 }
        end

        def count = @items.count { |item| item > 0 }
      end
    RUBY
    "spec/spec_helper.rb" => <<~RUBY,
      # frozen_string_literal: true
      $VERBOSE = true
      Warning[:strict_unused_block] = true
      def Warning.warn(message, **) = raise(message.to_s)
    RUBY
    "spec/totals_spec.rb" => <<~RUBY
      # frozen_string_literal: true
      require_relative "spec_helper"
      require_relative "../app/totals"

      RSpec.describe Totals do
        it("adds the positive items") { expect(Totals.new([1, -2, 3]).sum).to eq(4) }
        it("counts the positive items") { expect(Totals.new([1, -2, 3]).count).to eq(2) }
      end
    RUBY
  }

  def judged
    test_tree(files, "kimera-strict-fixture") do |fixture|
      test_outcome(cwd: fixture, arguments: ["--operators", "comparison", "--no-gate", "--jobs", "1"])
    end
  end

  def flipped(run) = run.results.filter_map { |row| [row["line"], row["status"]] if row["mutated"] == "item < 0" }

  it "judges memoized and warm mutants as a quiet suite would", :aggregate_failures do
    run = judged
    expect(run.counts).to(include("error" => 0, "harness_error" => 0), run.output)
    expect(flipped(run)).to(eq([[8, "killed"], [11, "killed"]]), run.output)
    expect(run.output).not_to(include("may be ignored"))
  end

  # R6B2-M3: Ruby settles whether a method uses its block as it compiles it, and
  # the warm overlay compiles every mutant of `join` into one, so `if false`,
  # which leaves `join` no yield, raised the warning only when baked alone.
  def pair = {
    "app/pair.rb" => <<~RUBY,
      # frozen_string_literal: true
      class Pair
        def initialize(left, right)
          @left = left
          @right = right
        end

        def join
          if block_given?
            yield([@left, @right])
          else
            [@left, @right]
          end
        end
      end
    RUBY
    "spec/spec_helper.rb" => files.fetch("spec/spec_helper.rb"),
    "spec/pair_spec.rb" => <<~RUBY
      # frozen_string_literal: true
      require_relative "spec_helper"
      require_relative "../app/pair"

      RSpec.describe Pair do
        it("joins with a block") { expect(Pair.new(1, 2).join { |both| both }).to eq([1, 2]) }
      end
    RUBY
  }

  it "kills the mutant that leaves a method no yield, as a suite that raises the warning does" do
    run = test_tree(pair, "kimera-pair") { |tree| test_outcome(cwd: tree, arguments: %w[--operators conditional]) }
    expect(run.results.map { |row| [row["mutated"].lines.first.strip, row["status"]] }).to(
      eq([["if true", "survived"], ["if false", "killed"]]), run.output
    )
  end
end
