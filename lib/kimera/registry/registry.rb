# frozen_string_literal: true

require "json"
require_relative "mutation_point"

class Kimera::Registry
  FORMAT_VERSION = 1

  attr_reader :points, :operators, :root

  def initialize(points: [], operators: [], root: ".")
    @points = points
    @operators = operators
    @root = root
  end

  def <<(point)
    @points << point
    @_groups = nil
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
      "points" => points.map(&:to_h)
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
      new(root: hash["root"] || ".", operators: hash["operators"] || [], points: cast(hash["points"]))
    end

    def load(path)
      from_h(JSON.parse(File.read(path, encoding: Encoding::UTF_8)))
    end

    private

    def cast(points)
      Array(points).map { |p| Kimera::MutationPoint.from_h(p) }
    end
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
