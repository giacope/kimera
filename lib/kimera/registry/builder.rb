# frozen_string_literal: true

require_relative "../operators"
require_relative "../self_protection"
require_relative "mutation_point"
require_relative "registry"

class Kimera::RegistryScan
  OWN_FIRST = 1_000_001

  def initialize(operators: Kimera::Operators.build, root: ".", shielded: true, numbering: Numbering.new)
    @operators = operators
    @base = root
    @shielded = shielded
    @numbering = numbering
  end

  def build(paths)
    numbering = Kimera::RegistryScan::Numbering.new(paths.any? { |path| own?(path) } ? OWN_FIRST : 1)
    scans = paths.sort.filter_map { |path| ingest(path, numbering) }
    Kimera::Registry.new(
      operators: @operators.map(&:key), root: located,
      points: scans.flat_map(&:points), unmutated: scans.flat_map(&:regions)
    )
  end

  def source(source, file:)
    scanned = scan(source, file, @numbering)
    Kimera::Registry.new(
      operators: @operators.map(&:key), root: located, points: scanned.points, unmutated: scanned.regions
    )
  end

  private

  def root = @_root ||= File.expand_path(@base)
  def located = root == Dir.pwd ? "." : root

  def own?(path) = Kimera::SelfProtection.new(path).own?

  def ingest(path, numbering)
    return if @shielded && Kimera::SelfProtection.new(path).protected?
    scan(File.read(path, encoding: Encoding::UTF_8), relative(path), numbering)
  rescue Errno::ENOENT
    nil
  rescue SystemCallError, IOError => error
    Kimera::RegistryScan::Unread.new(relative(path), error.message)
  end

  def scan(source, file, numbering)
    Kimera::RegistryScan::SourceFile.new(source, file: file, operators: @operators, numbering: numbering)
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
require_relative "unread"
