# frozen_string_literal: true

require "kimera/cli/coverage_minimum"

RSpec.describe(Kimera::CLI::CoverageMinimum) do
  def ungated?(source) = described_class.ungated?(source)

  it "flags a floor in any receiver form", :aggregate_failures do
    expect(ungated?("SimpleCov.minimum_coverage 90\n")).to(be(true))
    expect(ungated?("SimpleCov.start { minimum_coverage(line: 100, branch: 90) }\n")).to(be(true))
    expect(ungated?("SimpleCov.configure do\n  minimum_coverage_by_file 80\nend\n")).to(be(true))
  end

  it "passes over a helper with no floor call", :aggregate_failures do
    expect(ungated?("SimpleCov.start\n")).to(be(false))
    expect(ungated?("# minimum_coverage 90 once lived here\nSimpleCov.start\n")).to(be(false))
    expect(ungated?("SimpleCov.maximum_coverage_drop 5 # not a minimum_coverage\n")).to(be(false))
  end

  # giacope/kimera#19: pundit's spec/spec_helper.rb.
  it "passes over a floor under a condition that reads ENV, whatever the key", :aggregate_failures do
    expect(ungated?(<<~RUBY)).to(be(false))
      if ENV["COVERAGE"]
        require "simplecov"
        SimpleCov.start { add_filter "/spec/" }
        SimpleCov.minimum_coverage_by_file line: 100, branch: 100
      end
    RUBY
    expect(ungated?(%(SimpleCov.minimum_coverage 90 unless ENV.key?("NO_FLOOR")\n))).to(be(false))
    expect(ungated?(%(SimpleCov.minimum_coverage 90 if ENV.fetch("CI", nil)\n))).to(be(false))
    expect(ungated?(%(ENV.include?("CI") ? minimum_coverage(90) : nil\n))).to(be(false))
    expect(ungated?(%(::ENV["CI"] && SimpleCov.minimum_coverage(90)\n))).to(be(false))
    expect(ungated?(%(ENV["SKIP"] || SimpleCov.minimum_coverage(90)\n))).to(be(false))
    expect(ungated?(%(if RUBY_ENGINE == "jruby"\nelsif ENV["CI"] == "1"\n  minimum_coverage 90\nend\n))).to(be(false))
  end

  it "passes over a floor in a case on ENV", :aggregate_failures do
    expect(ungated?(%(case ENV["FLOOR"]\nwhen "strict" then minimum_coverage 100\nend\n))).to(be(false))
    expect(ungated?(%(case\nwhen ENV["CI"] then minimum_coverage 100\nelse minimum_coverage 50\nend\n))).to(be(false))
    expect(ungated?(%(case ENV["FLOOR"]\nin "strict" then minimum_coverage 100\nend\n))).to(be(false))
    expect(ungated?(%(case RUBY_ENGINE\nwhen "ruby" then minimum_coverage 100\nend\n))).to(be(true))
  end

  it "passes over a floor after an early exit guarded by ENV", :aggregate_failures do
    expect(ungated?(%(return unless ENV["COVERAGE"]\n\nSimpleCov.minimum_coverage 90\n))).to(be(false))
    expect(ungated?(%(exit if ENV["NO_COVERAGE"]\nminimum_coverage 90\n))).to(be(false))
    expect(ungated?(%(abort("no") unless ENV["CI"]\nminimum_coverage 90\n))).to(be(false))
    expect(ungated?(%(exit! unless ENV["CI"]\nminimum_coverage 90\n))).to(be(false))
    expect(ungated?(%(ENV["COVERAGE"] or return\nminimum_coverage 90\n))).to(be(false))
    expect(ungated?(%(SimpleCov.start do\n  next unless ENV["CI"]\n  minimum_coverage 90\nend\n))).to(be(false))
    expect(ungated?(%(loop do\n  break unless ENV["CI"]\n  minimum_coverage 90\nend\n))).to(be(false))
  end

  it "flags a floor before the guard, or after a guard that doesn't exit or doesn't read ENV", :aggregate_failures do
    expect(ungated?(%(minimum_coverage 90\nreturn unless ENV["COVERAGE"]\n))).to(be(true))
    expect(ungated?(%(puts "coverage" if ENV["COVERAGE"]\nminimum_coverage 90\n))).to(be(true))
    expect(ungated?(%(return unless defined?(SimpleCov)\nminimum_coverage 90\n))).to(be(true))
  end

  # Kimera's runs set KIMERA and leave everything else as it was: a Ruby
  # version, a gem check or a constant is as true under Kimera as in the
  # user's own run, so the floor still trips.
  it "flags a floor under a condition that doesn't read ENV", :aggregate_failures do
    expect(ungated?(%(if RUBY_ENGINE == "ruby"\n  SimpleCov.minimum_coverage 90\nend\n))).to(be(true))
    expect(ungated?(%(SimpleCov.minimum_coverage 90 if defined?(SimpleCov)\n))).to(be(true))
    expect(ungated?(%(puts "floor" if SimpleCov.minimum_coverage(90) || ENV["CI"]\n))).to(be(true))
  end

  it "trusts a helper that mentions KIMERA, as before" do
    expect(ungated?(%(minimum_coverage 90 unless kimera? # KIMERA\n))).to(be(false))
  end

  it "falls back to the text match when the helper doesn't parse", :aggregate_failures do
    expect(ungated?(%(if ENV["CI"]\n  minimum_coverage 90\nend\nSimpleCov.start do\n))).to(be(true))
    expect(ungated?("SimpleCov.start do\n")).to(be(false))
  end
end
