# frozen_string_literal: true

class Kimera::Frameworks::MinitestSuite::Hooks
  INSTALLED = true

  def initialize(loaders)
    @loaders = loaders
  end

  def disarmed
    Minitest.seed ||= 1
    Minitest::Test.prepend(Kimera::TestExit::Test)
    disarm
    self
  end

  def start; end

  def finish
    return unless @loaders.delete?(Process.pid)
    hooks = Minitest.class_variable_get(:@@after_run)
    Kimera::Frameworks::AfterRun.new(hooks).call
  end

  private

  def disarm
    Minitest.class_variable_set(:@@installed_at_exit, INSTALLED)
  rescue NameError, ArgumentError
    Minitest.define_singleton_method(:run) { |*| true }
  end
end
