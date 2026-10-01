# frozen_string_literal: true

class Kimera::Overlay::Source
  def initialize(text)
    @text = text
  end

  def evaluate(path)
    Kimera::Warnings.silence { TOPLEVEL_BINDING.eval(Kimera::SuperclassPin.pin(@text), path) }
  end
end
