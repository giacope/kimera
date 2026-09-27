# frozen_string_literal: true

require_relative "../error"

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

  class << self
    def build(failed, messages, command, workers: {}, stacks: {})
      new(summary(failed, messages, command, workers: workers, stacks: stacks))
    end

    def lost(reason) = LOSSES.fetch(reason, CRASH)

    def relapsed(reason) = lost(reason) + ALONE

    def mirrored(reason, hint)
      new(
        "isolated baseline is not green: the unmutated suite fails in a mirror of the project\n  " \
          "#{reason.gsub("\n", "\n    ")}\n#{hint}"
      )
    end

    def summary(failed, messages, command, workers: {}, stacks: {})
      text = "baseline suite is not green: #{failed.join(", ")}"
      text += appendix(failed, messages, stacks)
      text += Kimera::Execution::BaselineFailure::Breakdown.new(failed, workers).to_s
      "#{text}\n  reproduce without kimera: #{command}"
    end

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
