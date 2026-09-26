# frozen_string_literal: true

require_relative "../operators"
require_relative "../self_protection"
require_relative "mutation_point"
require_relative "registry"

class Kimera::RegistryScan
  def initialize(operators: nil, root: nil, shielded: true)
    @chosen = operators
    @base = root
    @shielded = shielded
  end

  def build(paths)
    fresh.tap do |registry|
      paths.sort.each { |path| ingest(registry, path) }
    end
  end

  def source(source, file:)
    fresh.tap { |registry| collect(registry, source, file) }
  end

  private

  def operators = @_operators ||= @chosen || Kimera::Operators.build
  def root = @_root ||= File.expand_path(@base || Dir.pwd)
  def numbering = @_numbering ||= Kimera::RegistryScan::Numbering.new

  def fresh
    Kimera::Registry.new(operators: operators.map(&:key), root: relative(root))
  end

  def ingest(registry, path)
    return if @shielded && Kimera::SelfProtection.protected?(path)
    collect(registry, File.read(path, encoding: Encoding::UTF_8), relative(path))
  rescue Errno::ENOENT
    nil
  end

  def collect(registry, source, file)
    Kimera::RegistryScan::SourceFile
      .new(source, file: file, operators: operators, numbering: numbering)
      .points.each { |point| registry << point }
    registry
  end

  def relative(path)
    abs = File.expand_path(path)
    return "." if abs == root
    return path unless abs.start_with?("#{root}/")
    abs[(root.length + 1)..]
  end
end

require_relative "numbering"
require_relative "source_file"
require_relative "tally"
