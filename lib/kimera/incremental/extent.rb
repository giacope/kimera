# frozen_string_literal: true

require "json"
require "pathname"

module Kimera
  module Incremental
  end
end

class Kimera::Incremental::Extent
  class Whole
    def initialize(root)
      @root = root
    end

    def of(names) = names.select { File.file?(path(it)) }.to_h { [it, lines(it)] }

    private

    def path(name) = File.join(@root.to_s, name)

    def lines(name) = 1.upto(File.open(path(name), "rb") { |io| io.each_line.count }).to_set
  end

  class Reached
    MAP = "tmp/kimera/coverage.json"
    LACKING = "kimera: --since-scope impact: %s, so the tests changed since add no files; " \
      "a full run with --reuse-coverage stores a map that does"

    def initialize(root, errors)
      @root = root
      @errors = errors
    end

    def files(names)
      document = read
      tests = touched(document, names.to_set)
      Hash(document["coverage"]).filter_map { |file, ids| file if ids.any? { tests.include?(it) } }
    end

    private

    def touched(document, names)
      files = document.fetch("test_files") { {}.tap { lacking("the coverage map at #{MAP} names no test's file") } }
      files.filter_map { |id, file| id if names.include?(Pathname(file).cleanpath.to_s) }.to_set
    end

    def read
      JSON.parse(File.read(File.join(@root.to_s, MAP), encoding: Encoding::UTF_8))
    rescue Errno::ENOENT
      {}.tap { lacking("no coverage map is stored at #{MAP}") }
    rescue JSON::ParserError
      {}.tap { lacking("#{MAP} is not JSON") }
    end

    def lacking(reason) = @errors.puts(format(LACKING, reason))
  end

  class Lines
    def initialize(diff)
      @diff = diff
    end

    def changes = @diff.lines
  end

  class Files
    def initialize(diff, root)
      @diff = diff
      @root = root
    end

    def changes = Whole.new(@root).of(@diff.names)
  end

  class Impact
    def initialize(diff, root, errors)
      @diff = diff
      @root = root
      @errors = errors
    end

    def changes
      names = @diff.names
      Whole.new(@root).of(names | Reached.new(@root, @errors).files(names))
    end
  end

  PHRASES = {
    "lines" => ->(since, files) { "on lines changed since #{since} (#{files} changed files)" },
    "files" => ->(since, files) { "in the #{files} files changed since #{since}" },
    "impact" => ->(since, files) { "in #{files} files changed since #{since} or reached by the tests changed since" }
  }.freeze

  def initialize(name, root = ".", errors: $stderr)
    @name = String(name)
    @root = root
    @errors = errors
  end

  def changes(diff) = kind(diff).changes

  def phrase(since, files) = PHRASES.fetch(@name).call(since, files)

  private

  def kind(diff)
    {
      "lines" => -> { Lines.new(diff) },
      "files" => -> { Files.new(diff, @root) },
      "impact" => -> { Impact.new(diff, @root, @errors) }
    }.fetch(@name).call
  end
end
