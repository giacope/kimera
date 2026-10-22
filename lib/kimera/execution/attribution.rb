# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Attribution
  STRIPPED = %w[lib/ app/ src/].freeze
  UNITS = { "spec" => "spec", "spec/unit" => "spec", "test" => "test", "test/unit" => "test" }.freeze
  GLOB = /[*?\[{]/
  MATCH = File::FNM_PATHNAME | File::FNM_EXTGLOB

  def initialize(rules = {})
    @rules = rules
  end

  def own?(test, source)
    conventional(source).any? { |pattern| File.fnmatch?(pattern, test, MATCH) } || ruled?(test, source)
  end

  def expected(source) = conventional(source).first(2)

  def strict? = true

  def admits?(source) = own?(yield, source)

  private

  def conventional(source)
    base = source.delete_suffix(".rb")
    trimmed = STRIPPED.filter_map { |root| base.delete_prefix(root) if base.start_with?(root) }
    kinds = base.start_with?("app/") ? trimmed.filter_map { |rest| rest.split("/", 2)[1] } : []
    [*trimmed, base, *kinds].uniq.flat_map { |stem| named(stem) }
  end

  def named(stem)
    folder, name = File.split(stem)
    ["spec/#{stem}_spec.rb", "test/#{stem}_test.rb", File.join("test", folder, "test_#{name}.rb").sub("/./", "/")] +
      UNITS.flat_map { |root, kind| ["#{root}/#{stem}_#{kind}.rb", "#{root}/#{stem}/**/*_#{kind}.rb"] }
  end

  def ruled?(test, source)
    @rules.any? do |glob, patterns|
      next false unless File.fnmatch?(glob, source, MATCH)
      path = source.delete_prefix(prefix(glob)).delete_suffix(".rb")
      filled = Array(patterns).map { |pattern| pattern.gsub("{path}", path).gsub("{name}", File.basename(path)) }
      filled.any? { |pattern| File.fnmatch?(pattern, test, MATCH) }
    end
  end

  def prefix(glob) = glob.split("/").take_while { |part| !part.match?(GLOB) }.map { |part| "#{part}/" }.join
end

require_relative "open_attribution"
