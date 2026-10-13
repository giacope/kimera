# frozen_string_literal: true

require "fileutils"
require "tmpdir"

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

  def project(root)
    files.each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), body)
    end
  end

  def hit(report) = report.fetch("results").select { |row| row["line"] == 5 }

  def statuses(report) = report.fetch("results").map { |row| row["status"] }

  it "judges it against the whole suite in order, in a fresh mirror" do
    Dir.mktmpdir("kimera-order") do |root|
      project(root)
      test_run(cwd: root, arguments: ["--no-progress", "--operators", "all"]) do |output, report, _status|
        expect(report).not_to(be_nil, output)
        expect(statuses(report)).not_to(include("no_coverage"), output)
        expect(hit(report).select { |row| row["label"] == "return => return nil" }.map { |row| row["status"] })
          .to(eq(["killed"]))
      end
    end
  end

  it "says why it has no covering test when it is not judged again" do
    Dir.mktmpdir("kimera-order") do |root|
      project(root)
      flags = ["--no-progress", "--no-rejudge", "--operators", "all"]
      test_run(cwd: root, arguments: flags) do |output, report, _status|
        uncovered = report.fetch("results").select { |row| row["status"] == "no_coverage" }
        expect(uncovered).not_to(be_empty, output)
        expect(uncovered.map { |row| [row["line"], row["detail"]] }.uniq).to(eq([[5, Kimera::MutationPoint::ORDER_REASON]]))
      end
    end
  end

  it "names the tests that pass only in order when the baseline is order-dependent" do
    Dir.mktmpdir("kimera-order") do |root|
      project(root)
      File.write(File.join(root, "spec", "memo_spec.rb"), <<~RUBY)
        require_relative "../app/memo"

        RSpec.describe Memo do
          it("computes a key") { expect(Memo.fetch(:a) { 1 }).to eq(1) }
          it("finds the key the last test stored") { expect(Memo.fetch(:a) { 2 }).to eq(1) }
        end
      RUBY
      test_run(cwd: root, arguments: ["--no-progress", "--jobs", "1"]) do |output, _report, status|
        expect(status).to(eq(1))
        expect(output).to(include("baseline suite is order-dependent: ./spec/memo_spec.rb[1:2]"))
        expect(output).to(include("the suite is order-dependent: these pass when the whole suite runs in order"))
      end
    end
  end
end
