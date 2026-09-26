# frozen_string_literal: true

require_relative "../error"

module Kimera
  module Execution
  end
end

class Kimera::Execution::BaselineFailure < Kimera::Error
  MAX_DETAILS = 3
  MAX_MESSAGE = 300

  class << self
    def build(failed, messages, command)
      new(summary(failed, messages, command))
    end

    def summary(failed, messages, command)
      text = "baseline suite is not green: #{failed.join(", ")}"
      text += appendix(failed, messages)
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
