# frozen_string_literal: true

class Kimera::Execution::Shift::Kill
  def initialize(test, failed, failures)
    @test = test
    @failed = failed
    @failures = failures
  end

  def noted(note) = self.class.new(@test, @failed, @failures.transform_values { |message| "#{note}: #{message}" })

  def conclude(&) = [self]

  def taught(killers) = killers.remembered(@test)

  def ruling(subject, fields)
    subject.verdict(:killed, failing_tests: @failed, detail: @failures.values.first, **fields)
  end
end
