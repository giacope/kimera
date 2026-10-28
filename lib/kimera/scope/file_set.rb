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

    def self.from_options(from_cli, options)
      new(Config::Precedence.new(from_cli, options[:paths]).chosen(DEFAULT_GLOBS), exclude: options[:exclude])
    end

    def self.default = new(DEFAULT_GLOBS)

    def initialize(patterns, include: [], exclude: [])
      @patterns = patterns
      @include = include
      @exclude = exclude
    end

    def to_s = to_a.join(", ")

    def to_a = Array(@patterns)

    def files = listed.sort

    def relative_to(root)
      base = File.expand_path(root)
      inside = Root.new(base)
      files.map { |file| inside.relative(file) }
    end

    def listed
      globbed = (Array(@patterns) + Array(@include)).flat_map { |pattern| Glob.new(pattern).found }.uniq
      Exclusion.new(@exclude).without(globbed)
    end

    def unused = Exclusion.new(@exclude).unused(FileSet.new(@patterns).files)
  end
end

require_relative "file_glob"
require_relative "file_exclusion"
