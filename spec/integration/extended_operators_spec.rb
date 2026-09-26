# frozen_string_literal: true

RSpec.describe("kimera run --operators all (end-to-end)") do
  it "synthesizes and evaluates every operator family without errors", :aggregate_failures do
    Dir.mktmpdir("kimera-extended-ops") do |fixture|
      FileUtils.mkdir_p(File.join(fixture, "app"))
      FileUtils.mkdir_p(File.join(fixture, "spec"))

      # Quoted heredoc keeps the regexp escapes intact.
      File.write(File.join(fixture, "app", "toolbox.rb"), <<~'RUBY')
        # frozen_string_literal: true
        class Toolbox
          def subtotal(prices, discount)
            (prices.uniq.sum * (100 - discount)) / 100
          end

          def label(name)
            name.nil? ? "unknown" : name&.strip
          end

          def tier(total)
            if !total.negative? && total > 100
              [:gold, :vip]
            else
              {tier: :basic}
            end
          end

          def window
            (1..7)
          end

          def evens(xs)
            result = xs.select { |x| x.even? }
            return result
          end

          def sku?(code)
            code.match?(/\A[A-Z]{2}\d{2}\z/)
          end

          def running_total(xs)
            sum = 0
            xs.each { |x| sum += x }
            sum
          end
        end
      RUBY

      File.write(File.join(fixture, "spec", "toolbox_spec.rb"), <<~RUBY)
        # frozen_string_literal: true
        require_relative "../app/toolbox"

        RSpec.describe Toolbox do
          subject(:box) { Toolbox.new }

          it { expect(box.subtotal([10, 10, 20], 10)).to eq(27) }
          it { expect(box.subtotal([50], 0)).to eq(50) }
          it { expect(box.label(nil)).to eq("unknown") }
          it { expect(box.label(" a ")).to eq("a") }
          it { expect(box.tier(101)).to eq([:gold, :vip]) }
          it { expect(box.tier(100)).to eq(tier: :basic) }
          it { expect(box.tier(-1)).to eq(tier: :basic) }
          it { expect(box.window.to_a).to eq([1, 2, 3, 4, 5, 6, 7]) }
          it { expect(box.evens([1, 2, 3, 4])).to eq([2, 4]) }
          it { expect(box.sku?("AB12")).to be(true) }
          it { expect(box.sku?("ab12")).to be(false) }
          it { expect(box.running_total([1, 2, 3])).to eq(6) }
        end
      RUBY

      test_run(cwd: fixture, args: ["--operators", "all"]) do |output, report, _status|
        expect(report).not_to(be_nil, "no report; output:\n#{output}")
        counts = report["counts"]
        expect(counts["total"]).to(be > 25)
        expect(counts["error"]).to(eq(0))
        expect(counts["timeout"]).to(eq(0))
        expect(counts["no_coverage"]).to(eq(0))
        expect(counts["killed"]).to(be > counts["survived"])
      end
    end
  end
end
