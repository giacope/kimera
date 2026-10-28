# frozen_string_literal: true

require "shellwords"

class Kimera::CLI::RspecOptions
  FILE = ".rspec"
  FLAGS = {
    "--pattern" => :pattern, "-P" => :pattern, "--exclude-pattern" => :exclude_pattern,
    "--default-path" => :default_path
  }.freeze
  LOADED = "Test discovery: .rspec leaves out %d of these files (--exclude-pattern %s), as `rspec` runs the " \
    "suite, and kimera loads them; add the pattern to exclude_tests"
  DEFAULT = "spec"
  LIST = /\s*,\s*/

  def initialize(root)
    @root = root
  end

  def tests(fallback = []) = globs(:pattern).then { |found| found.empty? ? fallback : found }

  def excluded = globs(:exclude_pattern)

  def loaded(files)
    left = excluded
    found = files & left.flat_map { |pattern| Dir.glob(File.join(@root, pattern)) }
    found.empty? ? [] : [["!", format(LOADED, found.size, left.join(", "))]]
  end

  private

  def globs(key) = options[key].to_s.split(LIST).map { |pattern| placed(pattern.delete_prefix("./")) }

  def placed(pattern)
    path = options.fetch(:default_path, DEFAULT)
    pattern.start_with?("#{path}/") ? pattern : File.join(path, pattern)
  end

  def options = @_options ||= read(words)

  def read(words)
    words.each_with_index.with_object({}) do |(word, index), found|
      flag, value = word.split("=", 2)
      key = FLAGS[flag]
      found[key] = value || words[index + 1] if key
    end
  end

  def words
    path = File.join(@root, FILE)
    File.file?(path) ? Shellwords.split(File.read(path, encoding: Encoding::UTF_8).scrub) : []
  rescue ArgumentError
    []
  end
end
