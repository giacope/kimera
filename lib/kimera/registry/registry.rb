# frozen_string_literal: true

require "json"
require_relative "mutation_point"
require_relative "mutant_keys"
require_relative "unmutated"

class Kimera::Registry
  FORMAT_VERSION = 1
  ROWS = ->(list, kind) { Array(list).map { |row| kind.from_h(row) } }

  attr_reader :points, :operators, :root, :unmutated

  def initialize(points: [], operators: [], root: ".", unmutated: [])
    @points = points
    @operators = operators
    @root = root
    @unmutated = unmutated
  end

  def narrow!(changed)
    @unmutated.select! { |region| region.touches?(Array(changed[region.file])) }
    self
  end

  def size
    @points.size
  end

  def count
    @points.sum { |p| p.mutants.size }
  end

  def files
    groups.keys
  end

  def summary
    "Found #{count} mutants at #{size} mutation " \
      "points across #{files.size} files."
  end

  def at(file)
    groups.fetch(file, [])
  end

  def index
    @_index ||= by_mutant_id { |_mutant, point| point }
  end

  def mutant(id)
    lookup[id]
  end

  def point(id)
    paired[id]
  end

  def keys
    @_keys ||= Kimera::MutantKeys.of(self)
  end

  def each
    return enum_for(:each) unless block_given?
    @points.each do |point|
      point.mutants.each { |m| yield(m, point) }
    end
  end

  def to_h
    identity.merge(stats)
  end

  def identity
    { "format_version" => FORMAT_VERSION, "root" => root, "operators" => operators }
  end

  def stats
    {
      "stats" => { "files" => files.size, "points" => size, "mutants" => count },
      "points" => points.map(&:to_h), "unmutated" => unmutated.map(&:to_h)
    }
  end

  def to_json(*)
    JSON.generate(to_h, *)
  end

  def write(path)
    File.write(path, JSON.pretty_generate(to_h))
    path
  end

  class << self
    def from_h(hash)
      points = ROWS.call(hash["points"], Kimera::MutationPoint)
      unmutated = ROWS.call(hash["unmutated"], Kimera::Unmutated)
      new(root: hash["root"] || ".", operators: hash["operators"] || [], points: points, unmutated: unmutated)
    end

    def parse(json) = from_h(JSON.parse(json))

    def from_file(path) = parse(File.read(path, encoding: Encoding::UTF_8))
  end

  private

  def groups
    @_groups ||= @points.group_by(&:file)
  end

  def paired
    @_paired ||= by_mutant_id { |mutant, point| [mutant, point] }
  end

  def lookup
    @_lookup ||= by_mutant_id { |mutant, _point| mutant }
  end

  def by_mutant_id
    each.with_object({}) { |(mutant, point), hash| hash[mutant.id] = yield(mutant, point) }
  end
end
