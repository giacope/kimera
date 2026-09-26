# frozen_string_literal: true

RSpec.describe("kimera run --since (incremental CI mode)") do
  # Only method b changes in the working tree.
  def test_build_repo(dir)
    FileUtils.mkdir_p(File.join(dir, "app", "models"))
    FileUtils.mkdir_p(File.join(dir, "spec"))
    test_write_calc(dir, body: "x < y")
    test_write_spec(dir, operator: :<)
    git(dir, "init -q")
    git(dir, "config user.email a@b.c")
    git(dir, "config user.name test")
    git(dir, "add -A")
    git(dir, "commit -q -m initial")
    test_write_calc(dir, body: "x <= y")
    test_write_spec(dir, operator: :<=)
  end

  def test_write_calc(dir, body:)
    File.write(File.join(dir, "app", "models", "calc.rb"), <<~RUBY)
      # frozen_string_literal: true
      class Calc
        def a(x, y)
          x > y
        end

        def b(x, y)
          #{body}
        end
      end
    RUBY
  end

  def test_cases(operator)
    if operator == :<
      "expect(c.b(1, 2)).to be(true)\n    expect(c.b(2, 2)).to be(false)"
    else
      "expect(c.b(2, 2)).to be(true)\n    expect(c.b(3, 2)).to be(false)"
    end
  end

  def test_write_spec(dir, operator:)
    File.write(File.join(dir, "spec", "calc_spec.rb"), <<~RUBY)
      # frozen_string_literal: true
      require_relative "../app/models/calc"

      RSpec.describe Calc do
        let(:c) { Calc.new }
        it("a") { expect(c.a(2, 1)).to be(true); expect(c.a(1, 2)).to be(false) }
        it "b" do
          #{test_cases(operator)}
        end
      end
    RUBY
  end

  def git(dir, args)
    system("git -C #{dir.shellescape} #{args} > /dev/null 2>&1") ||
      raise(Kimera::Error, "git #{args} failed")
  end

  it "evaluates only mutants on changed lines, and resumes from a session", :aggregate_failures do
    Dir.mktmpdir("kimera-incr") do |dir|
      test_build_repo(dir)
      session = File.join(dir, "session.json")

      test_run(cwd: dir, args: ["--since", "HEAD", "--session", session]) do |output, report, status|
        expect(report).not_to(be_nil, "no report; output:\n#{output}")
        expect(output).to(match(/Incremental: \d+ mutants on lines changed/))
        # `<=` -> `<` and `>=`, both on b's changed line.
        expect(report["counts"]["total"]).to(eq(2))
        expect(report["counts"]["killed"]).to(eq(2))
        expect(status).to(eq(0))
        expect(File).to(exist(session))
      end

      test_run(cwd: dir, args: ["--since", "HEAD", "--session", session]) do |_output, report, _status|
        expect(report["counts"]["total"]).to(eq(2))
        expect(report["counts"]["killed"]).to(eq(2))
      end
    end
  end
end

RSpec.describe("kimera run --max-survivors (threshold gating)") do
  it "passes when survivors are within the threshold and fails when they exceed it", :aggregate_failures do
    test_run(cwd: test_sample, args: ["--max-survivors", "5"]) do |_o, report, status|
      expect(report["counts"]["survived"]).to(eq(5))
      expect(status).to(eq(0))
    end

    test_run(cwd: test_sample, args: ["--max-survivors", "2"]) do |_o, _report, status|
      expect(status).to(eq(2))
    end
  end
end
