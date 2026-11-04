# frozen_string_literal: true

class Kimera::Frameworks::MinitestSuite::Hooks
  INSTALLED = true

  def initialize(loaders)
    @loaders = loaders
  end

  def disarmed
    Minitest.seed ||= 1
    # rubocop:disable-next Kata/NoMonkeyPatch -- a mutant that calls exit inside a test is a failure of that test, and only Minitest::Test#capture_exceptions, which lets SystemExit through, can record it as one
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
    # rubocop:disable-next Kata/NoMonkeyPatch -- minitest/autorun's at_exit would run the whole suite again after kimera's runs; a Minitest without @@installed_at_exit has no other switch
    Minitest.define_singleton_method(:run) { |*| true }
  end
end
