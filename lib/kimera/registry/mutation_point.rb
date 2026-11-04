# frozen_string_literal: true

require_relative "reason"

module Kimera
  Location =
    Struct.new(
      :start_offset, :span,
      :start_line, :start_column,
      :end_line, :end_column,
      keyword_init: true
    ) do
      def finish = start_offset + span

      def range = (start_line..end_line)

      def anchor(type) = [start_offset, finish, type]

      def covers?(offset) = offset.between?(start_offset, finish - 1)

      def starts_between?(from, to) = start_offset.between?(from, to)

      def starts_on?(line) = start_line == line

      def starts_at?(offset) = start_offset == offset

      def column?(column) = start_column + 1 == column

      def to_s = "#{start_line}:#{start_column + 1}"

      def within?(ranges)
        ranges.any? do |range|
          interior = ((range.start_offset + 1)..range.end_offset)
          interior.cover?(start_offset) && interior.cover?(finish)
        end
      end

      def inside?(from, to) = start_offset >= from && finish <= to

      def to_h = coordinates.merge(columns).merge(offsets)

      def position
        { "line" => start_line, "column" => start_column + 1 }.merge("end_line" => end_line, "end_column" => end_column)
      end
      private
      def coordinates = { "start_line" => start_line, "end_line" => end_line }
      def columns = { "start_column" => start_column, "end_column" => end_column }
      def offsets = { "start_offset" => start_offset, "length" => span }
      private(*members)
      class << self
        def parse(source)
          new(
            start_offset: source.start_offset, span: source.length,
            start_line: source.start_line, start_column: source.start_column,
            end_line: source.end_line, end_column: source.end_column
          )
        end

        def from_h(hash) = new(**hash.transform_keys { |key| key == "length" ? :span : key.to_sym })
      end
    end

  Mutant =
    Struct.new(:id, :label, :directive, keyword_init: true) do
      def to_s = label

      def to_i = id

      def rewrite(kind) = kind.new(directive)

      def to_h = { "id" => id, "label" => label, "directive" => directive }
      private(*members)
      def self.from_h(hash)
        new(id: hash["id"], label: hash["label"], directive: hash["directive"])
      end
    end
end

class Kimera::MutationPoint
  SAFE = true

  FIELDS = %i[point_id file operator node_type location original_source method_name mutants].freeze
  Marks =
    Struct.new(:safe, :reason, :revisit) do
      def safe? = safe

      def mark!(slot, text)
        self.safe = false if slot == :reason
        self[slot] = text
      end

      def texts(slot) = [self[slot]].compact

      def to_h = { "schema_safe" => safe, "unsafe_reason" => reason }
      private(*members, *members.map { :"#{it}=" })
    end
  FIELDS.each { |field| define_method(field) { @attributes[field] } }

  class << self
    def from_h(hash)
      new(
        point_id: hash["point_id"], file: hash["file"], operator: hash["operator"],
        node_type: hash["node_type"], original_source: hash["original_source"],
        location: Kimera::Location.from_h(hash["location"]), method_name: hash["method_name"],
        unsafe_reason: hash["unsafe_reason"], schema_safe: hash.fetch("schema_safe", SAFE),
        mutants: Array(hash["mutants"]).map { |m| Kimera::Mutant.from_h(m) }
      )
    end

    def none = new(mutants: [])
  end

  def initialize(**attributes)
    @attributes = attributes
  end

  def safe? = marks.safe?

  def mark!(reason) = reason.mark!(marks, ids)

  def reasons(kind) = kind.held(marks)

  def ids = mutants.map(&:to_i)

  def to_h = identity.merge(anchor).merge(verdict).merge("mutants" => mutants.map(&:to_h))

  private

  def marks(kind = Marks)
    @_marks ||= kind.new(@attributes.fetch(:schema_safe, SAFE), *@attributes.values_at(:unsafe_reason, :revisit))
  end

  def identity = { "point_id" => point_id, "file" => file, "operator" => operator }

  def anchor = { "node_type" => node_type, "location" => location.to_h, "original_source" => original_source }

  def verdict = { "method_name" => method_name }.merge(marks.to_h)
end
