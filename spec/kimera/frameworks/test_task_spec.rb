# frozen_string_literal: true

require "kimera/frameworks/test_task"
require "tmpdir"

# R6B3-M1: Rake::TestTask (and Minitest::TestTask) run the suite with `ruby -w`
# unless the task sets `warning = false`; mechanize's suite asserts on a
# deprecation it prints only `if $VERBOSE`, green under `rake test`, red without.
RSpec.describe(Kimera::Frameworks::TestTask) do
  def task(rakefile)
    Dir.mktmpdir do |root|
      File.write(File.join(root, "Rakefile"), rakefile) if rakefile
      yield(described_class.new(root))
    end
  end

  def flags(rakefile) = task(rakefile, &:flags)

  it "runs ruby -w as a test task does by default", :aggregate_failures do
    expect(flags("require 'rake/testtask'\nRake::TestTask.new { |t| t.pattern = 'test/*_test.rb' }\n")).to(eq(["-w"]))
    expect(flags("Rake::TestTask.new(:test) do |t|\n  t.libs << 'test'\nend\n")).to(eq(["-w"]))
    expect(flags("Minitest::TestTask.create\n")).to(eq(["-w"]))
    expect(flags("include Rake\nTestTask.new\n")).to(eq(["-w"]))
  end

  it "runs plain ruby when the test task turns warnings off, or no test task runs the suite", :aggregate_failures do
    expect(flags("Rake::TestTask.new do |t|\n  t.warning = false # noisy gems\nend\n")).to(eq([]))
    expect(flags("Rake::TestTask.new { |t| t.warning = nil }\n")).to(eq([]))
    expect(flags("Rails.application.load_tasks\ncreate(:db)\n")).to(eq([]))
    expect(flags(nil)).to(eq([]))
  end

  it "reads the task named test when the Rakefile holds several" do
    rakefile = "Rake::TestTask.new(:bench) { |t| t.warning = false }\nRake::TestTask.new(:test)\n"
    expect(flags(rakefile)).to(eq(["-w"]))
  end

  # Starts with warnings off, whatever ran before: compared with the state it
  # found, the task that keeps them off passed once a mutant had turned them on.
  def installed(rakefile)
    before = [$VERBOSE, Warning[:deprecated]]
    $VERBOSE = false
    Warning[:deprecated] = false
    task(rakefile, &:install)
    [$VERBOSE, Warning[:deprecated]]
  ensure
    $VERBOSE, Warning[:deprecated] = before
  end

  it "turns warnings on in this process only for a task that keeps them", :aggregate_failures do
    expect(installed("Rake::TestTask.new { |t| t.warning = false }\n")).to(eq([false, false]))
    expect(installed("Rake::TestTask.new\n")).to(eq([true, true]))
  end
end
