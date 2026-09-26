# frozen_string_literal: true

module Kimera
  module Execution
  end
end

Kimera::Execution::Trial =
  Struct.new(:id, :mirror, :synth, :file) do
    def stage(root)
      source = File.read(File.join(root, file), encoding: Encoding::UTF_8)
      target = File.join(mirror, file)
      File.write(target, synth.bake(file, source, id))
      [source, target]
    end
  end
