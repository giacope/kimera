# frozen_string_literal: true

require "kimera/execution/last_words"

# What a warm worker says on its way out when an exception ends it, so a
# crash verdict names the cause instead of just "crashed".
RSpec.describe(Kimera::Execution::LastWords) do
  let(:harness) { Kimera::Execution::StackDump::HARNESS }

  def raised(error, frames)
    error.tap { |failure| failure.set_backtrace(frames) }
  end

  it "names the exception and its frames up to kimera's own, relative to the project" do
    frames = [
      "#{Dir.pwd}/app/models/crasher.rb:15:in 'Crasher#notify'", "test/crasher_test.rb:10:in 'test_notify'",
      "#{harness}/execution/shift.rb:99:in 'outcome'", "test/after_harness.rb:1"
    ]
    error = raised(NoMemoryError.new("failed to allocate memory"), frames)
    expect(described_class.new(error).to_s).to(eq(<<~TEXT.chomp))
      NoMemoryError: failed to allocate memory
        app/models/crasher.rb:15:in 'Crasher#notify'
        test/crasher_test.rb:10:in 'test_notify'
    TEXT
  end

  it "shows kimera's own frames, capped, when the exception came from kimera" do
    frames = Array.new(20) { |index| "#{harness}/execution/shift.rb:#{index}" }
    lines = described_class.new(raised(RuntimeError.new("boom"), frames)).to_s.lines
    shown = frames.first(Kimera::Execution::StackDump::MAX_FRAMES).map { |frame| frame.delete_prefix("#{Dir.pwd}/") }
    expect(lines.map(&:strip)).to(eq(["RuntimeError: boom", *shown]))
  end

  it "says what to do about a signal nothing trapped, before frames a message might cut off" do
    words = described_class.new(raised(SignalException.new("TERM"), ["test/drain_test.rb:15"])).to_s
    advice = "nothing trapped SIGTERM: a test that signals its own process must trap the signal first, " \
      "or be left out with --exclude-test"
    expect(words).to(eq("SignalException: SIGTERM\n#{advice}\n  test/drain_test.rb:15"))
  end
end
