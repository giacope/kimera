# frozen_string_literal: true

class Kimera::Execution::Shift::Kill
  def initialize(test, failed_ids, failures)
    @test = test
    @failed_ids = failed_ids
    @failures = failures
  end

  def noted(note) = self.class.new(@test, @failed_ids, @failures.transform_values { |message| "#{note}: #{message}" })

  def conclude(&) = [self]

  def taught(killers) = killers.remember(@test)

  def ruling(subject, fields)
    subject.verdict(:killed, failing_tests: @failed_ids, detail: @failures.values.first, **fields)
  end
end
