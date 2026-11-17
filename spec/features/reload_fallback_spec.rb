# frozen_string_literal: true

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

  def tag = {
    "app/tag.rb" => <<~RUBY,
      # frozen_string_literal: true
      class Tag
        def initialize(text) = @text = text

        def to_s = @text

        def shout = self.to_s.upcase

        private

        def upcase = @text.upcase
      end
    RUBY
    "spec/tag_spec.rb" => <<~RUBY
      # frozen_string_literal: true
      require_relative "../app/tag"

      RSpec.describe Tag do
        it { expect(Tag.new("q3").shout).to eq("Q3") }
      end
    RUBY
  }

  it "lets a mutant that leaves a bare self call the private method the real edit would" do
    run = test_tree(tag, "kimera-tag") { |tree| test_outcome(cwd: tree, arguments: %w[--operators method_unwrap]) }
    unwrapped = run.results.to_h { |row| [row["label"], row.values_at("status", "detail")] }
    expect(unwrapped.fetch("delete .to_s")).to(eq(["survived", nil]), run.output)
  end
end
