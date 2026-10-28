# frozen_string_literal: true

module Kimera::Execution::Shift::Lapse
  def noted(_note) = self

  def conclude(&) = self

  def ruling(subject, fields) = subject.verdict(:timeout, detail: detail, **fields)
end
