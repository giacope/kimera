# frozen_string_literal: true

# On the schema path a memoized mutant would falsely survive.
RSpec.describe("reload fallback for memoized mutants") do
  it "kills a memoized comparison mutant via the reload path", :aggregate_failures do
    Dir.mktmpdir("kimera-reload-fixture") do |fixture|
      FileUtils.mkdir_p(File.join(fixture, "app", "models"))
      FileUtils.mkdir_p(File.join(fixture, "spec"))

      File.write(File.join(fixture, "app", "models", "rate.rb"), <<~RUBY)
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

      File.write(File.join(fixture, "spec", "rate_spec.rb"), <<~RUBY)
        # frozen_string_literal: true
        require_relative "../app/models/rate"

        RSpec.describe Rate do
          it { expect(Rate.new(10).multiplier).to eq(1) }
          it { expect(Rate.new(20).multiplier).to eq(2) }
        end
      RUBY

      test_run(cwd: fixture) do |output, report, _status|
        expect(report).not_to(be_nil, "no report; output:\n#{output}")
        expect(report["counts"]["survived"]).to(eq(0), "memoized mutant wrongly survived: #{report["results"].inspect}")
        expect(report["counts"]["killed"]).to(be >= 2)
        expect(report["counts"]["error"]).to(eq(0))
      end
    end
  end
end
