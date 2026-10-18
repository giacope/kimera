# frozen_string_literal: true

require "open3"
require_relative "../error"

module Kimera
  module Incremental
  end
end

class Kimera::Incremental::DiffError < Kimera::Error; end

class Kimera::Incremental::GitDiff
  FILE_HEADER = %r{\A\+\+\+ b/(.*)\n?\z}
  HUNK_HEADER = /\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/
  BASEFLAGS = %w[diff --relative --unified=0 --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/].freeze

  class << self
    def parse(text) = Changes.new.feed(text.dup.force_encoding(Encoding::UTF_8).scrub)
  end

  class Changes
    def initialize
      @files = {}
    end

    def feed(text)
      text.each_line.reduce([nil, 0]) { |(file, pending), line| advance(line, file, pending) }
      @files
    end

    private

    def advance(line, file, pending)
      return [file, pending - 1] if pending.positive? && line.start_with?("+")
      header = line.match(FILE_HEADER)
      return [named(header), pending] if header
      hunk = line.match(HUNK_HEADER)
      hunk ? collect(hunk, file) : [file, pending]
    end

    def named(header)
      path = header[1]
      path unless path == File::NULL
    end

    def collect(match, file)
      span = match[2]
      pending = span ? Integer(span, 10) : 1
      range(file, Integer(match[1], 10), pending) if file && pending.positive?
      [file, pending]
    end

    def range(file, start, pending)
      set = (@files[file] ||= Set.new)
      (start...(start + pending)).each { |line| set << line }
    end
  end

  def initialize(since:, root: ".", paths: nil)
    @since = since
    @root = root
    @paths = paths
  end

  def lines
    out, ok = read
    raise(failure) unless ok
    self.class.parse(out)
  end

  def files
    lines.keys
  end

  private

  def failure
    Kimera::Incremental::DiffError.new(
      "git diff against #{@since.inspect} failed (unknown ref, not a git repository, or git missing)#{shallow}"
    )
  end

  def shallow
    out, = Open3.capture2("git", "-C", @root.to_s, "rev-parse", "--is-shallow-repository", err: File::NULL)
    out.strip == "true" ? "; this clone is shallow, so fetch the base ref (actions/checkout: fetch-depth: 0)" : ""
  rescue Errno::ENOENT
    ""
  end

  def read
    out, _error, status = Open3.capture3(*command)
    [out, status.success?]
  rescue Errno::ENOENT
    ["", false]
  end

  def command
    invocation = ["git", "-C", @root.to_s, *BASEFLAGS, base]
    invocation += ["--", *Array(@paths)] if @paths
    invocation
  end

  def base
    since = @since.to_s
    out, status = Open3.capture2("git", "-C", @root.to_s, "merge-base", since, "HEAD", err: File::NULL)
    status.success? ? out.strip : since
  rescue Errno::ENOENT
    since
  end
end
