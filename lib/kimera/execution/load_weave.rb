# frozen_string_literal: true

require_relative "../support/warnings"
require_relative "../synthesis/overlay"

module Kimera
  module Execution
  end
end

class Kimera::Execution::LoadWeave
  UNSERVED = proc {}
  private_constant(:UNSERVED)

  def initialize(registry, overlays = Kimera::Overlay)
    @registry = registry
    @overlays = overlays
  end

  def during(files)
    opened.merge!(files)
    weave = self
    below = beneath
    hook = Module.new { define_method(:load_iseq) { |path| weave.compiled(path) { below.call(path) } } }
    # rubocop:disable-next Sekisho/NoMonkeyPatch -- Ruby asks RubyVM::InstructionSequence alone for load_iseq as it loads a file, so a refinement or a decorator is never called
    RubyVM::InstructionSequence.singleton_class.prepend(hook)
    yield
  ensure
    opened.clear
  end

  def woven(file, &) = weaves.fetch(file, &)

  def compiled(path, &)
    file = opened.delete(path)
    return yield unless file
    guarded(file, path, @overlays.new(@registry).synthesize(file, File.read(path, encoding: Encoding::UTF_8)), &)
  rescue StandardError, ScriptError
    yield
  end

  private

  def beneath(sequences = RubyVM::InstructionSequence)
    sequences.respond_to?(:load_iseq) ? sequences.method(:load_iseq) : UNSERVED
  end

  def weaves = @_weaves ||= {}

  def opened = @_opened ||= {}

  def guarded(file, path, result)
    return yield if result.empty?
    Kimera::Warnings.silenced.during { RubyVM::InstructionSequence.compile(result.to_s, path, path) }
      .tap { weaves.store(file, result.guarded) }
  end
end
