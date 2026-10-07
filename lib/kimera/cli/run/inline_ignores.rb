# frozen_string_literal: true

require "prism"
require_relative "../../error"
require_relative "../../operators"

class Kimera::CLI::Run::InlineIgnores
  MARKER = /\A#\s*kimera:disable(?<next>-next-line)?(?<rest>(?:[\s:].*)?)\z/
  CLAUSE = /\A(?<operators>[\w\s,]*?)\s*:\s*(?<reason>.*)\z/
  FORM = "# kimera:disable[-next-line] [OPERATOR ...]: REASON"

  def initialize(registry, root:)
    @registry = registry
    @root = root
  end

  def rules = @registry.files.flat_map { |file| scan(file) }

  private

  def scan(file)
    path = File.join(@root, file)
    return [] unless File.file?(path)
    Prism.parse_comments(File.read(path, encoding: Encoding::UTF_8)).filter_map { |comment| rule(file, comment) }
  end

  def rule(file, comment)
    location = comment.location
    marker = MARKER.match(location.slice.strip)
    marker && entry(file, location.start_line, marker)
  end

  def entry(file, line, marker)
    clause = CLAUSE.match(marker[:rest].strip)
    reason = clause&.[](:reason).to_s.strip
    absent(file, line) if reason.empty?
    { file: file, starts: line + (marker[:next] ? 1 : 0), reason: reason }.merge(operators(clause[:operators]))
  end

  def operators(listed)
    keys = listed.split(/[\s,]+/).reject(&:empty?)
    return {} if keys.empty?
    Kimera::Operators.validate!(keys)
    { operator: keys }
  end

  def absent(file, line) = raise(Kimera::UsageError, "#{file}:#{line}: kimera:disable needs a reason (#{FORM})")
end
