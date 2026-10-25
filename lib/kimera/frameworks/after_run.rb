# frozen_string_literal: true

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::AfterRun
  COVERAGE = %r{/simplecov[^/]*/lib/}

  def initialize(hooks, errors: $stderr)
    @hooks = hooks
    @errors = errors
  end

  def call = @hooks.reverse_each { |hook| settle(hook) unless coverage?(hook) }

  private

  def coverage?(hook) = where(hook).match?(COVERAGE)

  def settle(hook)
    hook.call
  rescue SystemExit => error
    note(hook, "called exit(#{error.status})")
  rescue StandardError, ScriptError => error
    note(hook, "raised #{error.class}: #{error.message}")
  end

  def note(hook, what)
    place = where(hook).delete_prefix("#{Dir.pwd}#{File::SEPARATOR}")
    @errors.puts("kimera: the suite's Minitest.after_run hook at #{place} #{what}; kimera went on")
  end

  def where(hook) = Array(hook.source_location).join(":")
end
