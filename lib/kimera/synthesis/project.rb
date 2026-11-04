# frozen_string_literal: true

require "fileutils"
require_relative "overlay"

module Kimera
  module Synthesis
  end
end

class Kimera::Synthesis::Project
  class Manifest
    def initialize(files = {}.freeze, mutant_files = {}.freeze, unsafe_mutants = [].freeze)
      @files = files
      @mutant_files = mutant_files
      @unsafe_mutants = unsafe_mutants
    end

    def recorded(file, destination, mutant_ids, unsafe)
      placed = mutant_ids.to_h { |id| [id, file] }
      self.class.new(
        @files.merge(file => destination).freeze, @mutant_files.merge(placed).freeze,
        [*@unsafe_mutants, *unsafe].freeze
      )
    end

    def summary(written, out)
      unsafe = @unsafe_mutants.size
      routed = unsafe.zero? ? [] : ["  #{unsafe} mutants routed to reload fallback (memoization)."]
      ["Synthesized #{written} files to #{out}.", "  #{@mutant_files.size} mutants on the schema path.", *routed]
    end
  end

  def initialize(registry, root: ".", manifest: Manifest.new, synth: Kimera::Overlay.new(registry))
    @registry = registry
    @root = root
    @manifest = manifest
    @synth = synth
  end

  def write(outdir)
    target = File.expand_path(outdir)
    @registry.to_h.keys.reduce(@manifest) do |manifest, file|
      source = File.join(root, file)
      next manifest unless File.file?(source)
      result = @synth.synthesize(file, File.read(source, encoding: Encoding::UTF_8))
      destination = File.join(target, file)
      emit(destination, result)
      result.record(manifest, destination)
    end
  end

  private

  def root
    @_root ||= File.expand_path(@root)
  end

  def emit(destination, result)
    FileUtils.mkdir_p(File.dirname(destination))
    result.write(destination)
  end
end
