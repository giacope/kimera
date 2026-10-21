# frozen_string_literal: true

require_relative "config"

module Kimera
  class FileSet
    DEFAULT_GLOBS = ["app/**/*.rb", "lib/**/*.rb"].freeze

    Root =
      Data.define(:path) do
        def relative(file)
          absolute = File.expand_path(file)
          inside = absolute.delete_prefix("#{path}/")
          inside == absolute ? file : inside
        end
      end

    attr_reader :patterns

    def self.from_options(from_cli, options)
      new(Config::Precedence.new(from_cli, options[:paths]).chosen(DEFAULT_GLOBS), exclude: options[:exclude])
    end

    def initialize(patterns, include: [], exclude: [])
      @patterns = patterns
      @include = include
      @exclude = exclude
    end

    def files = listed.sort

    def listed = without((Array(@patterns) + Array(@include)).flat_map { |pattern| resolve(pattern).sort }.uniq)

    def unused
      files = FileSet.new(@patterns).files
      Array(@exclude).reject do |pattern|
        resolved = resolve(pattern).to_set
        files.any? { |file| resolved.include?(file) || matches?(file, [pattern]) }
      end
    end

    def without(files)
      patterns = Array(@exclude)
      excluded = patterns.flat_map { |p| resolve(p) }.to_set
      files.reject { |file| excluded.include?(file) || matches?(file, patterns) }
    end

    private

    def resolve(pattern)
      return Dir.glob(File.join(pattern, "**", "*.rb")) if File.directory?(pattern)
      Dir.glob(pattern).select { |f| File.file?(f) && f.end_with?(".rb") }
    end

    def matches?(file, patterns)
      Array(patterns).any? { |p| File.fnmatch?(p, file, File::FNM_PATHNAME) }
    end
  end
end
