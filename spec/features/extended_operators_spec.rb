# frozen_string_literal: true

RSpec.describe("kimera run --operators all (end-to-end)") do
  def toolbox
    <<~'RUBY'
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
  end

  def toolbox_spec
    <<~RUBY
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
  end

  def ran
    test_tree({ "app/toolbox.rb" => toolbox, "spec/toolbox_spec.rb" => toolbox_spec }, "kimera-extended-ops") do |root|
      test_outcome(cwd: root, arguments: ["--operators", "all"])
    end
  end

  def both_modes(source, tests, operator)
    test_tree({ "app/subject.rb" => source, "spec/subject_spec.rb" => tests }) do |root|
      [[], ["--isolated"]].map do |mode|
        test_outcome(cwd: root, arguments: ["--operators", operator, *mode])
      end
    end
  end

  it "synthesizes and evaluates every operator family without errors", :aggregate_failures do
    run = ran
    counts = run.report&.fetch("counts") || {}
    expect(counts.slice("error", "timeout", "no_coverage"))
      .to(eq({ "error" => 0, "timeout" => 0, "no_coverage" => 0 }), run.output)
    expect(counts["total"]).to(be > 25)
    expect(counts["killed"]).to(be > counts["survived"])
  end

  it "keeps parenthesized flip-flops and implicit regexp matches conditional in both execution modes" do
    source = <<~RUBY
      class Windows
        def selected(values)
          values.select do |value|
            if ((value == 2)..(value == 4))
              true
            else
              false
            end
          end
        end

        def excluded(values)
          values.select do |value|
            if !((value == 2)..(value == 4))
              true
            else
              false
            end
          end
        end

        def matching(words)
          words.select do |word|
            $_ = word
            if (/a/)
              true
            else
              false
            end
          end
        end
      end
    RUBY
    tests = <<~RUBY
      require_relative "../app/subject"
      RSpec.describe Windows do
        it { expect(Windows.new.selected([0, 1, 2, 3, 4, 5])).to eq([2, 3, 4]) }
        it { expect(Windows.new.excluded([0, 1, 2, 3, 4, 5])).to eq([0, 1, 5]) }
        it { expect(Windows.new.matching(["no", "cat", "yes", "apple"])).to eq(["cat", "apple"]) }
      end
    RUBY
    both_modes(source, tests, "conditional,negation").each do |run|
      expect([run.status, run.counts.values_at("total", "killed")]).to(eq([0, [7, 7]]), run.output)
    end
  end

  it "does not capture a closure's local from another branch of its guard" do
    source = <<~RUBY
      class Captures
        def value
          (-> { [1] in [x]; false }.call || ([2] in [x]))
          x
        end

        def block_value
          ([1].any? { |number; kept| x = number; false } || ([2] in [x]))
          x
        end

        def default_value
          (->(arg = (x = 1)) { raise "lost default local" unless -> { x }.call == arg; false }.call || (x = 2))
          x
        end
      end
    RUBY
    tests = <<~RUBY
      require_relative "../app/subject"
      RSpec.describe Captures do
        it { expect([Captures.new.value, Captures.new.block_value, Captures.new.default_value]).not_to include(nil) }
      end
    RUBY
    both_modes(source, tests, "boolean_connective").each do |run|
      expect([run.status, run.counts.values_at("total", "killed")]).to(eq([0, [3, 3]]), run.output)
    end
  end
end
