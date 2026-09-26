# frozen_string_literal: true

module Kimera
  Location =
    Struct.new(
      :start_offset, :span,
      :start_line, :start_column,
      :end_line, :end_column,
      keyword_init: true
    ) do
      def finish
        start_offset + span
      end

      def range
        (start_line..end_line)
      end

      def within?(from, to)
        interior = ((from + 1)..to)
        interior.cover?(start_offset) && interior.cover?(finish)
      end

      def to_h
        coordinates.merge(columns).merge(offsets)
      end

      def coordinates
        { "start_line" => start_line, "end_line" => end_line }
      end

      def columns
        { "start_column" => start_column, "end_column" => end_column }
      end

      def offsets
        { "start_offset" => start_offset, "length" => span }
      end
      class << self
        def parse(source)
          new(**extent(source), **corners(source))
        end

        def from_h(hash) = new(**hash.transform_keys { |key| key == "length" ? :span : key.to_sym })
        def extent(source) = { start_offset: source.start_offset, span: source.length }
        def anchor(source) = { start_line: source.start_line, start_column: source.start_column }
        def corners(source) = anchor(source).merge(end_line: source.end_line, end_column: source.end_column)
      end
    end

  Mutant =
    Struct.new(:id, :label, :directive, keyword_init: true) do
      def to_h
        { "id" => id, "label" => label, "directive" => directive }
      end

      def self.from_h(hash)
        new(id: hash["id"], label: hash["label"], directive: hash["directive"])
      end

      def self.of(id, variant)
        new(id: id, label: variant.label, directive: variant.directive)
      end
    end
end

class Kimera::MutationPoint
  CLASS_BODY_REASON = "class-body DSL (runs at load; evaluate with --isolated)"
  UNMUTATABLE = "unmutatable: "
  SAFE = true

  FIELDS = %i[point_id file operator node_type location original_source method_name mutants unsafe_reason].freeze
  FIELDS.each { |field| define_method(field) { @attributes[field] } }

  class << self
    def from_h(hash)
      new(**plain(hash), **rich(hash))
    end

    private

    def plain(hash)
      { point_id: hash["point_id"], file: hash["file"], operator: hash["operator"] }
        .merge(node_type: hash["node_type"], original_source: hash["original_source"])
    end

    def rich(hash)
      { location: Kimera::Location.from_h(hash["location"]), method_name: hash["method_name"] }
        .merge(unsafe_reason: hash["unsafe_reason"], schema_safe: hash.fetch("schema_safe", SAFE))
        .merge(mutants: Array(hash["mutants"]).map { |m| Kimera::Mutant.from_h(m) })
    end
  end

  def initialize(**attributes)
    @attributes = attributes
  end

  def body?
    unsafe_reason == CLASS_BODY_REASON
  end

  def reloadable?
    !body? && !unmutatable?
  end

  def unmutatable?
    unsafe_reason.to_s.start_with?(UNMUTATABLE)
  end

  def unmutatable!(detail)
    unsafe!("#{UNMUTATABLE}#{detail}")
  end

  def safe
    @attributes.fetch(:schema_safe, SAFE)
  end

  def unsafe!(reason)
    @attributes[:schema_safe] = false
    @attributes[:unsafe_reason] = reason
  end

  def taint!(ranges)
    return self unless safe?
    hit = ranges.find { |range| range.contains?(location.start_offset, location.finish) }
    unsafe!(hit.reason) if hit
    self
  end

  def ids
    mutants.map(&:id)
  end

  def project(*fields)
    fields.map { |field| public_send(field) }
  end

  def safe?
    safe
  end

  def to_h
    identity.merge(anchor).merge(verdict).merge("mutants" => mutants.map(&:to_h))
  end

  def identity
    { "point_id" => point_id, "file" => file, "operator" => operator }
  end

  def anchor
    { "node_type" => node_type, "location" => location.to_h, "original_source" => original_source }
  end

  def verdict
    { "method_name" => method_name, "schema_safe" => safe, "unsafe_reason" => unsafe_reason }
  end

  NONE = new(mutants: []).freeze
end
