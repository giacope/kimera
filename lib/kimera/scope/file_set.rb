# frozen_string_literal: true

require_relative "config"
require_relative "foreign_file"

module Kimera
  class FileSet
    DEFAULT_GLOBS = ["app/**/*.rb", "lib/**/*.rb"].freeze
    private_constant(:DEFAULT_GLOBS)

    class Root
      def initialize(path)
        @path = path
      end

      def relative(file)
        absolute = File.expand_path(file)
        inside = absolute.delete_prefix("#{path}/")
        inside == absolute ? file : inside
      end

      private

      attr_reader :path
    end

    attr_reader :patterns

    def self.from_options(from_cli, options)
      new(Config::Precedence.new(from_cli, options[:paths]).chosen(DEFAULT_GLOBS), exclude: options[:exclude])
    end

    def self.default = new(DEFAULT_GLOBS)

    def initialize(patterns, include: [], exclude: [])
      @patterns = patterns
      @include = include
      @exclude = exclude
    end

    def to_s = Array(@patterns).join(", ")

    def files = listed.sort

    def relative_to(root)
      base = File.expand_path(root)
      inside = Root.new(base)
      files.map { |file| inside.relative(file) }
    end

    def listed = without((Array(@patterns) + Array(@include)).flat_map { |pattern| found(pattern) }.uniq)

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

    def found(pattern)
      matched = resolve(pattern).sort
      File.file?(pattern) ? matched : matched.reject { |file| Kimera::ForeignFile.new(file).foreign? }
    end

    def resolve(pattern)
      return Dir.glob(File.join(pattern, "**", "*.rb")) if File.directory?(pattern)
      Dir.glob(pattern).select { |f| File.file?(f) && f.end_with?(".rb") }
    end

    def matches?(file, patterns)
      Array(patterns).any? { |p| File.fnmatch?(p, file, File::FNM_PATHNAME) }
    end
  end
end
