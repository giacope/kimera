# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Two mutants of Catalog.load poison the memoized class-level table: once a
# test reloads it under the mutant, the table stays wrong after the
# switch-off. Each run starts in a fresh process, so the warm pass judges them
# itself. A mutant that makes its process exit can't be judged warm; it is
# judged again in a fresh mirror, which can't judge it either.
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

          def finish(code)
            exit!(3) if code.negative?
            code
          end
        end
      end
    RUBY
    File.write(File.join(root, "spec", "catalog_spec.rb"), <<~RUBY)
      require_relative "../app/catalog"

      RSpec.describe Catalog do
        after { described_class.reset! }

        it("names the dollar") { expect(described_class.name(:usd)).to eq("Dollar") }

        it("names the euro") { expect(described_class.name(:eur)).to eq("Euro") }

        it("finishes with a clean code") { expect(described_class.finish(0)).to eq(0) }
      end
    RUBY
  end

  def test_catalog_run(arguments)
    Dir.mktmpdir("kimera-rejudge") do |root|
      test_catalog(root)
      test_outcome(cwd: root, arguments: ["--no-progress", *arguments])
    end
  end

  def mirror_note = "judged in a fresh isolated mirror; the warm pass could not: worker crashed before result: exited 3"

  it "judges the poisoning mutants warm, and re-judges the one that ends its process" do
    run = test_catalog_run([])
    expect(run.verdicts.values_at(1, 2, 3, 4)).to(eq(%w[killed killed killed harness_error]), run.output)
    expect(run.results.first(4).map { |row| row.slice("note") }).to(eq([{}, {}, {}, { "note" => mirror_note }]))
    expect(run.output).to(include("the warm pass could not judge, judged again in fresh mirrors: 1 unjudged."))
  end

  it "leaves it unjudged with the warm detail under --no-rejudge" do
    run = test_catalog_run(["--no-rejudge"])
    expect(run.verdicts.values_at(1, 2, 3, 4)).to(eq(%w[killed killed killed harness_error]), run.output)
    expect(run.results.dig(3, "detail")).to(eq("worker crashed before result: exited 3"))
    expect([run.output, run.status]).to(match([a_string_including("gate failed: unjudged=1 > max_errors=0"), 2]))
  end
end
