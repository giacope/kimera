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
    def lines(**scope)
      new(**scope).lines
    end

    def files(**scope)
      new(**scope).files
    end

    def parse(text)
      Changes.new.feed(decoded(text))
    end

    private

    def decoded(text) = text.dup.force_encoding(Encoding::UTF_8).scrub
  end

  class Changes
    def initialize
      @files = {}
      @file = nil
      @pending = 0
    end

    def feed(text)
      text.each_line { |line| advance(line) }
      @files
    end

    private

    def advance(line)
      return @pending -= 1 if content?(line)
      header = line.match(FILE_HEADER)
      return @file = named(header) if header
      hunk = line.match(HUNK_HEADER)
      collect(hunk) if hunk
    end

    def content?(line) = @pending.positive? && line.start_with?("+")

    def named(header)
      path = header[1]
      path unless path == File::NULL
    end

    def collect(match)
      span = match[2]
      @pending = span ? Integer(span, 10) : 1
      range(Integer(match[1], 10)) if @file && @pending.positive?
    end

    def range(start)
      set = (@files[@file] ||= Set.new)
      (start...(start + @pending)).each { |line| set << line }
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
      "git diff against #{@since.inspect} failed (unknown ref, not a git repository, or git missing)"
    )
  end

  def read
    out, _error, status = Open3.capture3(*command)
    [out, status.success?]
  rescue Errno::ENOENT
    ["", false]
  end

  def command
    cmd = ["git", "-C", @root.to_s, *BASEFLAGS, @since.to_s]
    cmd += ["--", *Array(@paths)] if @paths
    cmd
  end
end
