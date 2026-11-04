# frozen_string_literal: true

require "json"
require_relative "mutation_point"
require_relative "mutant_keys"
require_relative "unmutated"

class Kimera::Registry
  FORMAT_VERSION = 1
  ROWS = ->(list, kind) { Array(list).map { |row| kind.from_h(row) } }

  def initialize(files: {}, operators: [], root: ".", unmutated: [])
    @files = files
    @operators = operators
    @root = root
    @unmutated = unmutated
  end

  def index
    @_index ||= by_mutant_id { |_mutant, point| point }
  end

  def texts(id, kind)
    mutant, point, file = paired.fetch(id)
    kind.new(point, mutant, file: file, root: @root).texts
  end

  def regions = yield(@unmutated)

  def narrowed(changed)
    kept = @unmutated.select { |region| region.touched?(changed) }
    self.class.new(files: @files, operators: @operators, root: @root, unmutated: kept)
  end

  def [](id, &) = paired.fetch(id, &)

  def each
    return enum_for(:each) unless block_given?
    @files.each do |file, points|
      points.each { |point| point.each { |mutant| yield(mutant, point, file) } }
    end
  end

  def to_a = @files.values.flatten(1)

  def to_h = @files

  def to_s = "Found #{count} mutants at #{to_a.size} mutation points across #{@files.size} files."

  def to_json(*)
    JSON.generate(identity.merge(stats), *)
  end

  class << self
    def from_h(hash)
      files = Array(hash["points"]).group_by { |row| row["file"] }.transform_values { ROWS.call(it, Kimera::MutationPoint) }
      unmutated = ROWS.call(hash["unmutated"], Kimera::Unmutated)
      new(root: hash["root"] || ".", operators: hash["operators"] || [], files: files, unmutated: unmutated)
    end

    def parse(json) = from_h(JSON.parse(json))

    def from_file(path) = parse(File.read(path, encoding: Encoding::UTF_8))
  end

  private

  def count = each.count

  def identity
    { "format_version" => FORMAT_VERSION, "root" => @root, "operators" => @operators }
  end

  def stats
    {
      "stats" => { "files" => @files.size, "points" => to_a.size, "mutants" => count },
      "points" => to_a.map(&:to_h), "unmutated" => @unmutated.map(&:to_h)
    }
  end

  def paired
    @_paired ||= by_mutant_id { |mutant, point, file| [mutant, point, file] }
  end

  def by_mutant_id
    each.with_object({}) { |(mutant, point, file), hash| hash[mutant.to_i] = yield(mutant, point, file) }
  end
end
