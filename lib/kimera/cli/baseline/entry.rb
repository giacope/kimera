# frozen_string_literal: true

require_relative "../../scope/ignore_list"

class Kimera::CLI::Baseline::Entry
  include Kimera::IgnoreList::Drift

  KILLING = %w[killed timeout error].freeze
  PRUNABLE = %i[killed stale].freeze

  attr_reader :fields

  def initialize(fields, rows, missing: :stale)
    @fields = fields
    @rows = rows
    @missing = missing
  end

  def kind
    return :out_of_scope if @rows.empty?
    hits.empty? ? @missing : verdict
  end

  def prunable? = PRUNABLE.include?(kind)

  def moved = exact.empty? ? hits.first&.fetch("line") : nil

  def statuses = hits.map { |row| row["verdict"] || row["status"] }.uniq

  def kept = moved ? @fields.merge("line" => moved) : @fields

  def place
    file, line, label = @fields.values_at("file", "line", "label")
    "#{[file, line].compact.join(":")}#{" → #{moved}" if moved} [#{label}]"
  end

  private

  def verdict
    return :surviving if statuses.include?("survived")
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
