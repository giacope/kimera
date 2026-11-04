# frozen_string_literal: true

require "json"
require_relative "mutation_point"
require_relative "mutant_keys"
require_relative "unmutated"

class Kimera::Registry
  FORMAT_VERSION = 1
  ROWS = ->(list, kind) { Array(list).map { |row| kind.from_h(row) } }

  def initialize(points: [], operators: [], root: ".", unmutated: [])
    @points = points
    @operators = operators
    @root = root
    @unmutated = unmutated
  end

  def index
    @_index ||= by_mutant_id { |_mutant, point| point }
  end

  def texts(point, mutant, kind) = kind.new(point, mutant, root: @root).texts

  def regions = yield(@unmutated)

  def narrowed(changed)
    kept = @unmutated.select { |region| region.touched?(changed) }
    self.class.new(points: @points, operators: @operators, root: @root, unmutated: kept)
  end

  def [](id, &) = paired.fetch(id, &)

  def each
    return enum_for(:each) unless block_given?
    @points.each do |point|
      point.mutants.each { |m| yield(m, point) }
    end
  end

  def to_a = @points.dup

  def to_h = groups

  def to_s = "Found #{count} mutants at #{@points.size} mutation points across #{groups.size} files."

  def to_json(*)
    JSON.generate(identity.merge(stats), *)
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

  def count = @points.sum { |p| p.mutants.size }

  def identity
    { "format_version" => FORMAT_VERSION, "root" => @root, "operators" => @operators }
  end

  def stats
    {
      "stats" => { "files" => groups.size, "points" => @points.size, "mutants" => count },
      "points" => @points.map(&:to_h), "unmutated" => @unmutated.map(&:to_h)
    }
  end

  def groups
    @_groups ||= @points.group_by(&:file)
  end

  def paired
    @_paired ||= by_mutant_id { |mutant, point| [mutant, point] }
  end

  def by_mutant_id
    each.with_object({}) { |(mutant, point), hash| hash[mutant.to_i] = yield(mutant, point) }
  end
end
