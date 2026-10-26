# frozen_string_literal: true

require "open3"

module Kimera
  class WorkTree
    SKIPPED = %w[.git tmp log node_modules].freeze
    BOUND = 50_000
    LISTED = 10

    def initialize(root, ignored: [])
      @given = root
      @ignored = ignored
    end

    def watch
      before = snapshot
      [yield, warning(changed(before))]
    end

    def snapshot = git? ? tracked : walked

    def changed(before)
      after = snapshot
      known = git? ? before.keys | after.keys : before.keys
      known.reject { |path| before[path] == after[path] || ignored?(path) }.sort
    end

    private

    def root = @_root ||= File.expand_path(@given)

    def warning(paths)
      return if paths.empty?
      shown = paths.first(LISTED).map { |path| "  #{path}" }
      hidden = paths.size - LISTED
      [
        "kimera: the run changed #{paths.size} tracked file(s) in the project; a test or a mutant wrote or " \
          "deleted them, so verdicts judged after that may be wrong (restore them, then rerun; " \
          "`kimera run --isolated` judges each mutant in a copy of the project):",
        *shown, (hidden.positive? ? "  … and #{hidden} more" : nil)
      ].compact.join("\n")
    end

    def git?
      _out, status = Open3.capture2e("git", "-C", root, "rev-parse", "--is-inside-work-tree")
      status.success?
    rescue SystemCallError
      false
    end

    def tracked
      out, = Open3.capture2("git", "-C", root, "status", "--porcelain", "--untracked-files=no", "-z")
      out.split("\0").each_with_object({}) do |entry, found|
        path = entry[3..]
        found[path] = [entry[0, 2], *stat(path)]
      end
    end

    def walked
      Dir.glob("**/*.rb", base: root).lazy
        .select { |path| File.file?(File.join(root, path)) }
        .first(BOUND).to_h { |path| [path, stat(path)] }
    end

    def stat(path)
      info = File.stat(File.join(root, path))
      [info.size, info.mtime.to_r]
    rescue SystemCallError
      [:missing]
    end

    def ignored?(path)
      full = File.expand_path(path, root)
      SKIPPED.include?(path.split("/").first) || @ignored.compact.any? { |kept| File.expand_path(kept, root) == full }
    end
  end
end
