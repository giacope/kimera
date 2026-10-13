# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# A second file wraps Order#total through alias_method, so the original body
# runs only through the alias. Its mutants must reach the tests through the
# alias, whichever of the two files sorts first.
RSpec.describe("kimera run on a method wrapped by an alias chain in another file (end-to-end)") do
  def files(wrapper) = {
    "app/order.rb" => <<~RUBY,
      class Order
        def initialize(sum) = @sum = sum

        def total
          s = @sum
          s >= 1000 ? s - 100 : s
        end
      end
    RUBY
    "app/#{wrapper}.rb" => <<~RUBY,
      require_relative "order"

      class Order
        alias_method :total_before_tax, :total

        def total
          t = total_before_tax
          t + (t / 10)
        end
      end
    RUBY
    "spec/order_spec.rb" => <<~RUBY
      require_relative "../app/#{wrapper}"

      RSpec.describe Order do
        it("adds tax") { expect(Order.new(250).total).to eq(275) }
        it("discounts from 1000 before tax") { expect([Order.new(1000).total, Order.new(999).total]).to eq([990, 1098]) }
      end
    RUBY
  }

  def project(root, wrapper)
    files(wrapper).each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), body)
    end
  end

  %w[order_tax a_tax].each do |wrapper|
    it "covers and kills the wrapped original's mutants when the wrapper is #{wrapper}.rb", :aggregate_failures do
      Dir.mktmpdir("kimera-alias") do |root|
        project(root, wrapper)
        test_run(cwd: root, args: ["--no-progress"]) do |output, report, status|
          expect(report).not_to(be_nil, output)
          original = report.fetch("results").select { |row| row["file"] == "app/order.rb" }
          expect(original).not_to(be_empty)
          expect(original.map { |row| row["status"] }.uniq).to(eq(["killed"]), output)
          expect(status).to(eq(0))
        end
      end
    end
  end
end
