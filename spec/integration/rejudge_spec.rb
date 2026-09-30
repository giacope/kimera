# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Two mutants of Catalog.load poison the memoized class-level table: once a
# test reloads it under the mutant, the table stays wrong after the switch-off,
# so the warm control run fails too and the warm pass can't judge them.
RSpec.describe("kimera run re-judges what the warm pass could not (end-to-end)", :aggregate_failures) do
  def test_catalog(root)
    FileUtils.mkdir_p([File.join(root, "app"), File.join(root, "spec")])
    File.write(File.join(root, "app", "catalog.rb"), <<~RUBY)
      require "json"

      class Catalog
        DATA = '{"usd": {"name": "Dollar"}, "eur": {"name": "Euro"}}'

        class << self
          def table = @table ||= load

          def load = JSON.parse(DATA, symbolize_names: true)

          def reset! = (@table = load)

          def name(code) = table.fetch(code).fetch(:name)
        end
      end
    RUBY
    File.write(File.join(root, "spec", "catalog_spec.rb"), <<~RUBY)
      require_relative "../app/catalog"

      RSpec.describe Catalog do
        after { described_class.reset! }

        it("names the dollar") { expect(described_class.name(:usd)).to eq("Dollar") }

        it("names the euro") { expect(described_class.name(:eur)).to eq("Euro") }
      end
    RUBY
  end

  def test_statuses(report) = report["results"].to_h { |row| [row["mutant_id"], row["status"]] }

  def test_catalog_run(args, &)
    Dir.mktmpdir("kimera-rejudge") do |root|
      test_catalog(root)
      test_run(cwd: root, args: ["--no-progress", *args], &)
    end
  end

  it "reports a poisoning mutant killed from a fresh mirror, keeping the warm detail as a note" do
    test_catalog_run([]) do |output, report, status|
      expect(report).not_to(be_nil, "no JSON report; output:\n#{output}")
      expect(test_statuses(report)).to(eq(1 => "killed", 2 => "killed", 3 => "killed"))
      notes = report["results"].first(2).map { |row| row["note"] }
      expect(notes).to(all(start_with("judged in a fresh isolated mirror; the warm pass could not: ")))
      expect(notes.last).to(include("also failed with the mutant switched off", "even on a fresh worker"))
      expect(report["results"].last).not_to(have_key("note"))
      expect(output).to(include("2 mutant(s) the warm pass could not judge, judged again in fresh mirrors: 2 killed."))
      expect(status).to(eq(0))
    end
  end

  it "leaves them unjudged, failing the default gate, under --no-rejudge" do
    test_catalog_run(["--no-rejudge"]) do |output, report, status|
      expect(test_statuses(report)).to(eq(1 => "harness_error", 2 => "harness_error", 3 => "killed"))
      expect(output).to(include("gate failed: unjudged=2 > max_errors=0"))
      expect(status).to(eq(2))
    end
  end
end
