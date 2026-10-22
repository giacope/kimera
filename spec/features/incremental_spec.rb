# frozen_string_literal: true

RSpec.describe("kimera run --since (incremental CI mode)") do
  # Only method b changes in the working tree.
  def test_build_repository(dir)
    FileUtils.mkdir_p(File.join(dir, "app", "models"))
    FileUtils.mkdir_p(File.join(dir, "spec"))
    test_write_calculation(dir, body: "x < y")
    test_write_spec(dir, operator: :<)
    git(dir, "init -q")
    git(dir, "config user.email a@b.c")
    git(dir, "config user.name test")
    git(dir, "add -A")
    git(dir, "commit -q -m initial")
    test_write_calculation(dir, body: "x <= y")
    test_write_spec(dir, operator: :<=)
  end

  def test_write_calculation(dir, body:)
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

  def git(dir, arguments)
    system("git -C #{dir.shellescape} #{arguments} > /dev/null 2>&1") ||
      raise(Kimera::Error, "git #{arguments} failed")
  end

  # Two runs over a repository's uncommitted change, sharing a session; each run's outcome.
  def resumed
    Dir.mktmpdir("kimera-incr") do |dir|
      test_build_repository(dir)
      arguments = ["--since", "HEAD", "--session", File.join(dir, "session.json")]
      first = test_outcome(cwd: dir, arguments: arguments)
      [first, File.exist?(File.join(dir, "session.json")), test_outcome(cwd: dir, arguments: arguments)]
    end
  end

  # `<=` -> `<` and `>=`, both on b's changed line.
  it "evaluates only mutants on changed lines, and resumes from a session", :aggregate_failures do
    first, saved, again = resumed
    expect(first.output).to(match(/Incremental: \d+ mutants on lines changed/))
    expect([first.report&.fetch("counts")&.values_at("total", "killed"), first.status, saved]).to(eq([[2, 2], 0, true]))
    expect(again.report&.fetch("counts")&.values_at("total", "killed")).to(eq([2, 2]))
  end
end
