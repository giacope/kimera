# frozen_string_literal: true

class Kimera::Overlay::Source
  def initialize(text)
    @text = text
  end

  def evaluate(path)
    Kimera::Warnings.silence { compiled(path).eval }
  end

  private

  def compiled(path)
    RubyVM::InstructionSequence.compile(Kimera::SuperclassPin.pin(@text), path, File.expand_path(path))
  end
end
