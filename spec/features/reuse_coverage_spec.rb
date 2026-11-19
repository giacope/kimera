# frozen_string_literal: true

require "open3"

RSpec.describe("kimera run --reuse-coverage (end-to-end)") do
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

  def one_file(path)
    kimera = [File.join(test_repository_root, "exe", "kimera"), "run", path, "--tests", "spec/**/*_spec.rb"]
    env = { "BUNDLE_GEMFILE" => File.join(test_repository_root, "Gemfile") }
    Open3.capture2e(env, "bundle", "exec", "ruby", *kimera, "--no-progress", "--no-report", chdir: dir).first
  end

  def verdicts(report) = report.fetch("results").map { |result| result.values_at("key", "status") }

  def head = `git -C #{dir.shellescape} rev-parse --short=7 HEAD`.strip

  it "keeps a full run's coverage map under --reuse-coverage, and reruns only the tests that reached the change" do
    write("app/models/calc.rb", "class Calc\n  def big?(x) = x >= 11\n\n  def small?(x) = x < 3\nend\n")
    expect(run("--since", "HEAD", "--reuse-coverage").first).to(
      include(
        "reusing the coverage map from #{head} (1 source and 0 test file(s) changed since): " \
          "the baseline runs 2 of 3 tests"
      )
    )
  end

  it "judges each mutant as a run that measures every test does" do
    write("app/models/calc.rb", "class Calc\n  def big?(x) = x >= 11\n\n  def small?(x) = x <= 2\nend\n")
    reused = verdicts(run("--since", "HEAD", "--reuse-coverage").last)
    expect([reused.size, reused]).to(eq([4, verdicts(run("--since", "HEAD").last)]))
  end

  it "reruns only an edited test file's tests, judging as a full baseline does", :aggregate_failures do
    write("app/models/word.rb", "class Word\n  def long?(word) = word.size >= 5\nend\n")
    write("spec/word_spec.rb", spec("word", "Word", ['long?("abcde")', 'long?("abcdef")']))
    output, report = run("--since", "HEAD")
    expect(output).to(include("(1 source and 1 test file(s) changed since): the baseline runs 2 of 4 tests"))
    expect(verdicts(report)).to(eq(verdicts(run("--since", "HEAD", "--no-reuse-coverage").last)))
  end

  it "reads the map on a run of one file, rerunning only the tests that reach it" do
    expect(one_file("app/models/word.rb")).to(include("the baseline runs 1 of 3 tests"))
  end

  it "runs every test, saying why, when a support file changed since" do
    write("app/models/word.rb", "class Word\n  def long?(word) = word.size >= 5\nend\n")
    write("spec/spec_helper.rb", "")
    expect(run("--since", "HEAD").first)
      .to(include("not reusing the stored coverage map: spec/spec_helper.rb changed; the baseline runs every test"))
  end
end
