# frozen_string_literal: true

# Memo's cache-hit branch runs only when an earlier test filled the key, so
# no test reaches it alone in a fresh process; the suite run in order does.
RSpec.describe("kimera run on code only an earlier test's state reaches (end-to-end)", :aggregate_failures) do
  def files = {
    "app/memo.rb" => <<~RUBY,
      module Memo
        @store = {}

        def self.fetch(key)
          return @store[key] if @store.key?(key)

          @store[key] = yield
        end
      end
    RUBY
    "spec/memo_spec.rb" => <<~RUBY
      require_relative "../app/memo"

      RSpec.describe Memo do
        it("computes a key") { expect(Memo.fetch(:a) { 1 }).to eq(1) }
        it("answers the same key again") { expect(Memo.fetch(:a) { 1 }).to eq(1) }
      end
    RUBY
  }

  def entangled = files.merge("spec/memo_spec.rb" => <<~RUBY)
    require_relative "../app/memo"

    RSpec.describe Memo do
      it("computes a key") { expect(Memo.fetch(:a) { 1 }).to eq(1) }
      it("finds the key the last test stored") { expect(Memo.fetch(:a) { 2 }).to eq(1) }
    end
  RUBY

  def judged(*flags, tree: files)
    arguments = ["--no-progress", "--operators", "all", *flags]
    test_tree(tree, "kimera-order") { |root| test_outcome(cwd: root, arguments: arguments) }
  end

  def statuses(run, label)
    run.results.select { |row| row["line"] == 5 && row["label"] == label }.map { |row| row["status"] }
  end

  it "judges it against the whole suite in order, in a fresh mirror" do
    run = judged
    expect(run.statuses).not_to(include("no_coverage"), run.output)
    expect(statuses(run, "return => return nil")).to(eq(["killed"]), run.output)
  end

  it "says why it has no covering test when it is not judged again" do
    run = judged("--no-rejudge")
    uncovered = run.results.select { |row| row["status"] == "no_coverage" }.map { |row| [row["line"], row["detail"]] }
    expect(uncovered.uniq).to(eq([[5, Kimera::MutationPoint::ORDER_REASON]]), run.output)
  end

  it "names the tests that pass only in order when the baseline is order-dependent" do
    run = judged("--jobs", "1", tree: entangled)
    expect(run.status).to(eq(1))
    expect(run.output).to(
      include(
        "baseline suite is order-dependent: ./spec/memo_spec.rb[1:2]",
        "the suite is order-dependent: these pass when the whole suite runs in order"
      )
    )
  end
end
