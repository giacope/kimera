# frozen_string_literal: true

module Kimera::Execution::Shift::Inconclusive
  def conclude = yield(self)

  def taught(killers) = killers

  def ruling(subject, _fields) = subject.verdict(:harness_error, detail: unjudged)
end
