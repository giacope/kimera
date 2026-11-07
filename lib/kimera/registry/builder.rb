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
    scans = paths.sort.flat_map { |path| ingest(path, numbering) { [] } }
    Kimera::Registry.new(
      operators: @operators.map(&:key), root: located,
      files: filed(scans), unmutated: scans.flat_map { |_file, scan| scan.regions }
    )
  end

  def source(source, file:)
    scanned = scan(source, file, @numbering)
    Kimera::Registry.new(
      operators: @operators.map(&:key), root: located, files: filed([[file, scanned]]), unmutated: scanned.regions
    )
  end

  private

  def root = @_root ||= File.expand_path(@base)
  def located(here = Dir.pwd) = root == here ? "." : root

  def own?(path) = Kimera::SelfProtection.new(path).own?

  def filed(scans)
    found = scans.map { |file, scan| [file, scan.points] }.reject { |_file, points| points.empty? }
    found.group_by(&:first).transform_values { |pairs| pairs.flat_map(&:last) }
  end

  def ingest(path, numbering)
    file = relative(path)
    return [] if @shielded && Kimera::SelfProtection.new(path).protected?
    [[file, scan(File.read(path, encoding: Encoding::UTF_8), file, numbering)]]
  rescue Errno::ENOENT
    yield
  rescue SystemCallError, IOError => error
    [[file, Kimera::RegistryScan::Unread.new(file, error.message)]]
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
