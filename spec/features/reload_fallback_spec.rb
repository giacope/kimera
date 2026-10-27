# frozen_string_literal: true

# On the schema path a memoized mutant would falsely survive.
RSpec.describe("reload fallback for memoized mutants") do
  def files = {
    "app/models/rate.rb" => <<~RUBY,
      # frozen_string_literal: true
      class Rate
        def initialize(base)
          @base = base
        end

        def multiplier
          @multiplier ||= (@base > 10 ? 2 : 1)
        end
      end
    RUBY
    "spec/rate_spec.rb" => <<~RUBY
      # frozen_string_literal: true
      require_relative "../app/models/rate"

      RSpec.describe Rate do
        it { expect(Rate.new(10).multiplier).to eq(1) }
        it { expect(Rate.new(20).multiplier).to eq(2) }
      end
    RUBY
  }

  it "kills a memoized comparison mutant via the reload path" do
    run = test_tree(files, "kimera-reload-fixture") { |fixture| test_outcome(cwd: fixture) }
    expect(run.counts).to(include("survived" => 0, "killed" => be >= 2, "error" => 0), run.output)
  end

  # R6B2-M2: the reload child watched `high?`, a one-line def that starts later
  # on the memoized mutant's line, not `reading`, the method that holds it.
  def meter = {
    "app/meter.rb" => <<~RUBY,
      # frozen_string_literal: true
      class Meter
        def initialize(level)
          @level = level
        end

        def reading
          @reading ||= Struct.new(:value) { def high? = value > 5 }.new(@level * 2 > 0 ? @level : 0)
        end
      end
    RUBY
    "spec/meter_spec.rb" => <<~RUBY
      # frozen_string_literal: true
      require_relative "../app/meter"

      RSpec.describe Meter do
        it { expect(Meter.new(3).reading.value).to eq(3) }
      end
    RUBY
  }

  def readings(run)
    run.results.filter_map { |row| row.values_at("status", "covering_tests") if row["method"] == "reading" }
  end

  it "watches the method that holds a memoized mutant, not a one-line def beside it on its line" do
    run = test_tree(meter, "kimera-meter") { |tree| test_outcome(cwd: tree, arguments: %w[--operators comparison]) }
    covering = ["./spec/meter_spec.rb[1:1]"]
    expect(readings(run)).to(eq([["survived", covering], ["killed", covering]]), run.output)
  end
end
