# frozen_string_literal: true

require_relative "../../scope/ignore_list"

class Kimera::CLI::Baseline::Entry
  include Kimera::IgnoreList::Drift

  KILLING = %w[killed timeout error].freeze
  SURVIVING = %w[survived uncovered_by_unit].freeze

  def initialize(fields, rows, missing: :stale)
    @fields = fields
    @rows = rows
    @missing = missing
  end

  def kind?(*kinds) = kinds.include?(kind)

  def status?(name) = statuses.include?(name)

  def moved? = exact.empty? && hits.any?

  def remark
    shown = statuses
    yield(to_s, kind, shown.empty? ? "" : " (#{shown.join(", ")})", @fields["reason"])
  end

  def to_h = moved? ? @fields.merge("line" => relocated) : @fields

  def to_s
    file, line, label = @fields.values_at("file", "line", "label")
    "#{[file, line].compact.join(":")}#{" → #{relocated}" if moved?} [#{label}]"
  end

  private

  def kind
    return :out_of_scope if @rows.empty?
    hits.empty? ? @missing : verdict
  end

  def statuses = hits.map { |row| row["verdict"] || row["status"] }.uniq

  def relocated = hits.first.fetch("line")

  def verdict
    return :surviving if statuses.intersect?(SURVIVING)
    (statuses - KILLING).empty? ? :killed : :unjudged
  end

  def anchors = @_anchors ||= @fields.except("file").transform_keys(&:to_sym)

  def matching(anchors) = @rows.select { |row| fits?(anchors, row) }

  def fits?(anchors, row)
    anchors.all? do |key, value|
      field = key.to_s
      !row.key?(field) || squeeze(value) == squeeze(row[field])
    end
  end

  def squeeze(value) = value.to_s.split.join(" ")
end
