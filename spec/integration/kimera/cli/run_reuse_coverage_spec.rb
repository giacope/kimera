# frozen_string_literal: true

# A full run stores its baseline's coverage map; an incremental run reuses it
# and reruns only the tests that reached the changed file, with the verdicts a
# run that measures every test gives.
RSpec.describe(Kimera::CLI::Run) do
  let(:dir) { Dir.mktmpdir("kimera-reuse") }

  before do
    write("app/models/calc.rb", "class Calc\n  def big?(x) = x > 10\n\n  def small?(x) = x < 3\nend\n")
    write("app/models/word.rb", "class Word\n  def long?(word) = word.size > 4\nend\n")
    write("spec/calc_spec.rb", spec("calc", "Calc", %w[big?(11) small?(2)]))
    write("spec/word_spec.rb", spec("word", "Word", ['long?("abcde")']))
    commit
    run("--reuse-coverage")
  end

  after { FileUtils.remove_entry(dir) }

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    File.write(File.join(dir, path), body)
  end

  def spec(file, name, calls)
    examples = calls.map { |call| "  it(#{call.inspect}) { expect(#{name}.new.#{call}).to be(true) }\n" }
    "require_relative \"../app/models/#{file}\"\nRSpec.describe(#{name}) do\n#{examples.join}end\n"
  end

  def commit
    [%w[init -q], %w[add -A], %w[-c user.email=a@b.c -c user.name=t commit -q -m initial]].each do |arguments|
      system("git", "-C", dir, *arguments, out: File::NULL, err: File::NULL)
    end
  end

  def run(*arguments)
    test_run(cwd: dir, arguments: ["--no-progress", *arguments]) { |output, report, _status| [output, report] }
  end

  def verdicts(report) = report.fetch("results").map { |result| result.values_at("key", "status") }

  def head = `git -C #{dir.shellescape} rev-parse --short=7 HEAD`.strip

  it "keeps a full run's coverage map under --reuse-coverage, and reruns only the tests that reached the change" do
    write("app/models/calc.rb", "class Calc\n  def big?(x) = x >= 11\n\n  def small?(x) = x < 3\nend\n")
    expect(run("--since", "HEAD", "--reuse-coverage").first).to(
      include("reusing the coverage map from #{head} (1 source file(s) changed since): the baseline runs 2 of 3 tests")
    )
  end

  it "judges each mutant as a run that measures every test does" do
    write("app/models/calc.rb", "class Calc\n  def big?(x) = x >= 11\n\n  def small?(x) = x <= 2\nend\n")
    reused = verdicts(run("--since", "HEAD", "--reuse-coverage").last)
    expect([reused.size, reused]).to(eq([4, verdicts(run("--since", "HEAD").last)]))
  end

  it "runs every test, saying why, when a test file changed since" do
    write("app/models/word.rb", "class Word\n  def long?(word) = word.size >= 5\nend\n")
    write("spec/word_spec.rb", spec("word", "Word", ['long?("abcdef")']))
    expect(run("--since", "HEAD", "--reuse-coverage").first)
      .to(include("not reusing the stored coverage map: spec/word_spec.rb changed; the baseline runs every test"))
  end
end
