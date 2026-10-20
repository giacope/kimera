# frozen_string_literal: true

class Kimera::Execution::BaselineFailure::Summary
  MAX_DETAILS = 3
  MAX_MESSAGE = 300
  SHARED = "if the reproduce command above fails too, the tests are red on their own; if it passes and " \
    "--jobs 1 is green, the suite shares state between workers (a directory, file or port): " \
    "use jobs: 1 until each test has its own"

  ORDERED = "the suite is order-dependent: these pass when the whole suite runs in order, but fail alone in a " \
    "fresh process, because they rely on state an earlier test leaves behind. Kimera runs every test in a process " \
    "of its own, so make each one set up what it needs:"

  Context = Data.define(:workers, :stacks, :jobs, :ordered)
  SERIAL = Context.new(workers: {}, stacks: {}, jobs: 1, ordered: [])

  def initialize(failed, messages, command, context = SERIAL)
    @failed = failed
    @messages = messages
    @command = command
    @context = context
  end

  def to_s
    text = "baseline suite is #{state}: #{listed}#{appendix}"
    text += Kimera::Execution::BaselineFailure::Breakdown.new(@failed, @context.workers).to_s
    "#{text}\n  reproduce without kimera: #{@command}#{order}#{shared}"
  end

  def listed
    count = @failed.size
    count < 2 ? @failed.join : "#{count} tests failed:#{Kimera::Listing.new(@failed).lines("    ")}"
  end

  private

  def state = (@failed - @context.ordered).empty? ? "order-dependent" : "not green"

  def order
    ordered = @context.ordered
    ordered.empty? ? "" : "\n  #{ORDERED}#{Kimera::Listing.new(ordered).lines("    ")}"
  end

  def shared
    jobs = @context.jobs
    jobs > 1 && (@failed - @context.ordered).any? ? "\n  ran on #{jobs} workers: #{SHARED}" : ""
  end

  def appendix
    items = @failed.first(MAX_DETAILS).filter_map { |id| detail(id) }
    items.empty? ? "" : "\n#{items.join("\n")}"
  end

  def detail(id)
    message = @messages[id]
    return unless message
    "  #{id}:\n    #{[truncate(message), @context.stacks[id]].compact.join("\n").gsub("\n", "\n    ")}"
  end

  def truncate(text)
    text.length > MAX_MESSAGE ? "#{text[0, MAX_MESSAGE]}…" : text
  end
end
