# frozen_string_literal: true

# The visibility operator end to end: the warm run flips a method private on
# activation, and its verdicts match the isolated tier's, which bakes
# `private(:name)` into a fresh copy of the project.
RSpec.describe("kimera run --operators visibility (end-to-end)") do
  def files = {
    "app/ledger.rb" => <<~RUBY,
      # frozen_string_literal: true
      class Ledger
        def total = entries.sum
        def entries = [1, 2]
        def audit = :ok
        def ghost = :real

        def method_missing(name, *args) = name == :ghost ? :ghosted : super
        def respond_to_missing?(name, include_private = false) = name == :ghost || super
      end
    RUBY
    "spec/ledger_spec.rb" => <<~RUBY
      # frozen_string_literal: true
      require_relative "../app/ledger"

      RSpec.describe Ledger do
        it { expect(Ledger.new.total).to eq(3) }
        it { expect(Ledger.new.__send__(:audit)).to eq(:ok) }
        it { expect(Ledger.new.ghost).to eq(:real) }
      end
    RUBY
  }

  def statuses(run) = run.results.to_h { |result| [result["method"], result["status"]] }

  def visibility(mode)
    arguments = ["--operators", "visibility", *mode]
    test_tree(files, "kimera-visibility") { |root| test_outcome(cwd: root, arguments: arguments) }
  end

  { "warm" => [], "isolated" => ["--isolated"] }.each do |tier, mode|
    it "kills a method tests call from outside, spares one called only inside or through send, #{tier}" do
      run = visibility(mode)
      expected = { "total" => "killed", "entries" => "survived", "audit" => "survived", "ghost" => "killed" }
      expect(statuses(run)).to(eq(expected), run.output)
    end
  end
end
