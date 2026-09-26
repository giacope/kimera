# frozen_string_literal: true

require "fileutils"
require_relative "overlay"

module Kimera
  module Synthesis
  end
end

class Kimera::Synthesis::Project
  Manifest =
    Struct.new(:files, :mutant_files, :unsafe_mutants, keyword_init: true) do
      def record(file, dest, result)
        files[file] = dest
        result.mutant_ids.each { |id| mutant_files[id] = file }
        unsafe_mutants.concat(result.skipped_unsafe)
      end
    end

  def initialize(registry, root: ".")
    @registry = registry
    @root = root
  end

  def write(outdir)
    outdir = File.expand_path(outdir)
    @registry.files.each { |file| copy(file, outdir) }
    manifest
  end

  private

  def manifest
    @_manifest ||= Manifest.new(files: {}, mutant_files: {}, unsafe_mutants: [])
  end

  def copy(file, outdir)
    source = File.join(root, file)
    return unless File.file?(source)
    emit(file, outdir, synth.synthesize(file, File.read(source, encoding: Encoding::UTF_8)))
  end

  def root
    @_root ||= File.expand_path(@root)
  end

  def synth
    @_synth ||= Kimera::Overlay.new(@registry)
  end

  def emit(file, outdir, result)
    dest = File.join(outdir, file)
    FileUtils.mkdir_p(File.dirname(dest))
    File.write(dest, result.source)
    manifest.record(file, dest, result)
  end
end
