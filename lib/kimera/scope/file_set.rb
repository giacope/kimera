# frozen_string_literal: true

require_relative "config"

module Kimera
  module FileSet
    DEFAULT_GLOBS = ["app/**/*.rb", "lib/**/*.rb"].freeze

    module_function

    def globs(from_cli, options)
      Config.prefer(from_cli, options[:paths], DEFAULT_GLOBS)
    end

    def scoped(from_cli, options)
      expand(globs(from_cli, options), exclude: options[:exclude])
    end

    def expand(patterns, include: [], exclude: [])
      exclude((Array(patterns) + Array(include)).flat_map { |pattern| resolve(pattern) }.uniq, exclude).sort
    end

    def relative(path, root)
      absolute = File.expand_path(path)
      absolute.start_with?("#{root}/") ? absolute[(root.length + 1)..] : path
    end

    def resolve(pattern)
      return Dir.glob(File.join(pattern, "**", "*.rb")) if File.directory?(pattern)
      Dir.glob(pattern).select { |f| File.file?(f) && f.end_with?(".rb") }
    end

    def unused(patterns, exclude)
      files = expand(patterns)
      Array(exclude).reject do |pattern|
        resolved = resolve(pattern).to_set
        files.any? { |file| resolved.include?(file) || matches?(file, [pattern]) }
      end
    end

    def exclude(files, exclude)
      patterns = Array(exclude)
      excluded = patterns.flat_map { |p| resolve(p) }.to_set
      files.reject { |file| excluded.include?(file) || matches?(file, patterns) }
    end

    def matches?(file, patterns)
      Array(patterns).any? { |p| File.fnmatch?(p, file, File::FNM_PATHNAME) }
    end
  end
end
