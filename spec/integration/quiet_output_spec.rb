# frozen_string_literal: true

RSpec.describe("worker output suppression") do
  # The markers are concatenated at runtime because the survivor report quotes
  # source lines verbatim. Only printed noise should match.
  def fixture(&)
    Dir.mktmpdir("kimera-noisy-fixture") do |fixture|
      FileUtils.mkdir_p(File.join(fixture, "app", "models"))
      FileUtils.mkdir_p(File.join(fixture, "spec"))
      write(fixture)
      test_run(cwd: fixture, &)
    end
  end

  def write(fixture)
    File.write(File.join(fixture, "app", "models", "loud.rb"), <<~RUBY)
      # frozen_string_literal: true
      class Loud
        def positive?(n)
          puts "LOUD_STDOUT_" + "NOISE"
          warn "LOUD_STDERR_" + "NOISE"
          n > 0
        end
      end
    RUBY
    File.write(File.join(fixture, "spec", "loud_spec.rb"), <<~RUBY)
      # frozen_string_literal: true
      require_relative "../app/models/loud"

      RSpec.describe Loud do
        it { expect(Loud.new.positive?(1)).to be(true) }
        it { expect(Loud.new.positive?(-1)).to be(false) }
        it { expect(Loud.new.positive?(0)).to be(false) }
      end
    RUBY
  end

  # "mutants [" is the progress bar, which must stay off without a tty (plain
  # progress lines take its place).
  it "keeps app noise out of kimera's output while still killing mutants", :aggregate_failures do
    fixture do |output, report, _status|
      expect(report).not_to(be_nil, "no report; output:\n#{output}")
      expect(report["counts"]["killed"]).to(be >= 1)
      expect(output).not_to(match(/LOUD_STDOUT_NOISE|LOUD_STDERR_NOISE|mutants \[/))
    end
  end
end
