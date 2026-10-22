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
end
