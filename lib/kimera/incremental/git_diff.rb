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
      files = {}
      current = nil
      decoded(text).each_line { |line| current = advance(files, current, line) }
      files
    end

    private

    def decoded(text) = text.dup.force_encoding(Encoding::UTF_8).scrub

    def advance(files, current, line)
      header = line.match(FILE_HEADER)
      return named(header) if header
      hunk = line.match(HUNK_HEADER)
      collect(files, current, hunk) if current && hunk
      current
    end

    def named(header)
      path = header[1]
      path unless path == File::NULL
    end

    def collect(files, file, match)
      span = match[2]
      count = span ? Integer(span, 10) : 1
      return if count.zero?
      range(files, file, Integer(match[1], 10), count)
    end

    def range(files, file, start, count)
      set = (files[file] ||= Set.new)
      (start...(start + count)).each { |line| set << line }
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
