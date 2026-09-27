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

  class << self
    def build(failed, messages, command, workers: {})
      new(summary(failed, messages, command, workers: workers))
    end

    def lost(reason) = LOSSES.fetch(reason, CRASH)

    def mirrored(reason, hint)
      new(
        "isolated baseline is not green: the unmutated suite fails in a mirror of the project\n  " \
          "#{reason.gsub("\n", "\n    ")}\n#{hint}"
      )
    end

    def summary(failed, messages, command, workers: {})
      text = "baseline suite is not green: #{failed.join(", ")}"
      text += appendix(failed, messages)
      text += Kimera::Execution::BaselineFailure::Breakdown.new(failed, workers).to_s
      "#{text}\n  reproduce without kimera: #{command}"
    end

    def appendix(failed, messages)
      items = details(failed, messages)
      items.empty? ? "" : "\n#{items.join("\n")}"
    end

    def details(failed, messages)
      failed.first(MAX_DETAILS).filter_map { |id| detail(id, messages[id]) }
    end

    def detail(id, message)
      return unless message
      "  #{id}:\n    #{truncate(message).gsub("\n", "\n    ")}"
    end

    def truncate(text)
      text.length > MAX_MESSAGE ? "#{text[0, MAX_MESSAGE]}…" : text
    end
  end
end

require_relative "baseline_failure/breakdown"
