# frozen_string_literal: true

require_relative "../error"
require_relative "../listing"

module Kimera
  module Execution
  end
end

class Kimera::Execution::BaselineFailure < Kimera::Error
  MAX_DETAILS = 3
  MAX_MESSAGE = 300
  LOSSES = { timeout: "its worker was killed at the hard timeout (--hard-timeout) before reporting a result" }.freeze
  CRASH = "its worker died before reporting a result"
  ALONE = ", and again when rerun alone"
  SHARED = "if these pass with --jobs 1, the suite shares state between workers (a directory, file or port); " \
    "use jobs: 1 until each test has its own"

  class << self
    def build(failed, messages, command, workers: {}, stacks: {}, jobs: 1)
      new(summary(failed, messages, command, workers: workers, stacks: stacks, jobs: jobs))
    end

    def lost(reason) = LOSSES.fetch(reason, CRASH)

    def relapsed(reason) = lost(reason) + ALONE

    def mirrored(reason, hint)
      new(
        "isolated baseline is not green: the unmutated suite fails in a mirror of the project\n  " \
          "#{reason.gsub("\n", "\n    ")}\n#{hint}"
      )
    end

    def summary(failed, messages, command, workers: {}, stacks: {}, jobs: 1)
      text = "baseline suite is not green: #{listed(failed)}"
      text += appendix(failed, messages, stacks)
      text += Kimera::Execution::BaselineFailure::Breakdown.new(failed, workers).to_s
      "#{text}\n  reproduce without kimera: #{command}#{shared(jobs)}"
    end

    def listed(failed)
      count = failed.size
      count < 2 ? failed.join : "#{count} tests failed:#{Kimera::Listing.lines(failed, "    ")}"
    end

    def shared(jobs) = jobs > 1 ? "\n  ran on #{jobs} workers: #{SHARED}" : ""

    def appendix(failed, messages, stacks = {})
      items = details(failed, messages, stacks)
      items.empty? ? "" : "\n#{items.join("\n")}"
    end

    def details(failed, messages, stacks = {})
      failed.first(MAX_DETAILS).filter_map { |id| detail(id, messages[id], stacks[id]) }
    end

    def detail(id, message, stacks = nil)
      return unless message
      "  #{id}:\n    #{[truncate(message), stacks].compact.join("\n").gsub("\n", "\n    ")}"
    end

    def truncate(text)
      text.length > MAX_MESSAGE ? "#{text[0, MAX_MESSAGE]}…" : text
    end
  end
end

require_relative "baseline_failure/breakdown"
