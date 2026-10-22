# frozen_string_literal: true

require_relative "../../support/warnings"

class Kimera::Overlay::Source
  def initialize(text)
    @text = text
  end

  def evaluate(path)
    Kimera::Warnings::SILENCED.during { compiled(path).eval }
  end

  private

  def compiled(path)
    RubyVM::InstructionSequence.compile(Kimera::SuperclassPin.new(@text).pinned, path, File.expand_path(path))
  end
end
