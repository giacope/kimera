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
    scans = paths.sort.filter_map { |path| ingest(path) }
    Kimera::Registry.new(
      operators: operators.map(&:key), root: relative(root),
      points: scans.flat_map(&:first), unmutated: scans.flat_map(&:last)
    )
  end

  def source(source, file:)
    points, regions = scan(source, file)
    Kimera::Registry.new(operators: operators.map(&:key), root: relative(root), points: points, unmutated: regions)
  end

  private

  def operators = @_operators ||= @chosen || Kimera::Operators.build
  def root = @_root ||= File.expand_path(@base || Dir.pwd)
  def numbering = @_numbering ||= Kimera::RegistryScan::Numbering.new

  def ingest(path)
    return if @shielded && Kimera::SelfProtection.new(path).protected?
    scan(File.read(path, encoding: Encoding::UTF_8), relative(path))
  rescue Errno::ENOENT
    nil
  end

  def scan(source, file)
    scanned = Kimera::RegistryScan::SourceFile.new(source, file: file, operators: operators, numbering: numbering)
    [scanned.points, scanned.regions]
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
