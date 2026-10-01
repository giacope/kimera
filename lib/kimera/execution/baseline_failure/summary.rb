# frozen_string_literal: true

class Kimera::Execution::BaselineFailure::Summary
  MAX_DETAILS = 3
  MAX_MESSAGE = 300
  SHARED = "if these pass with --jobs 1, the suite shares state between workers (a directory, file or port); " \
    "use jobs: 1 until each test has its own"

  Context = Data.define(:workers, :stacks, :jobs)
  SERIAL = Context.new(workers: {}, stacks: {}, jobs: 1)

  def initialize(failed, messages, command, context = SERIAL)
    @failed = failed
    @messages = messages
    @command = command
    @context = context
  end

  def to_s
    text = "baseline suite is not green: #{listed}#{appendix}"
    text += Kimera::Execution::BaselineFailure::Breakdown.new(@failed, @context.workers).to_s
    "#{text}\n  reproduce without kimera: #{@command}#{shared}"
  end

  def listed
    count = @failed.size
    count < 2 ? @failed.join : "#{count} tests failed:#{Kimera::Listing.lines(@failed, "    ")}"
  end

  private

  def shared
    jobs = @context.jobs
    jobs > 1 ? "\n  ran on #{jobs} workers: #{SHARED}" : ""
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
