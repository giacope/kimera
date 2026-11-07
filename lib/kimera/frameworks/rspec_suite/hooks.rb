# frozen_string_literal: true

class Kimera::Frameworks::RSpecSuite::Hooks
  def initialize(suites)
    @suites = suites
  end

  def start
    return unless @suites.add?(Process.pid)
    hooks(:@before_suite_hooks)
  end

  def finish
    return unless @suites.include?(Process.pid)
    hooks(:@after_suite_hooks)
  end

  private

  def hooks(store)
    config = RSpec.configuration
    context = RSpec::Core::SuiteHookContext.new(store.to_s, config.reporter)
    # rubocop:disable-next Kata/NoReflection -- RSpec keeps the before(:suite) and after(:suite) hooks in these fields and runs them only from its own runner, which a warm worker does not use
    config.instance_variable_get(store).each { |hook| hook.run(context) }
  end
end
