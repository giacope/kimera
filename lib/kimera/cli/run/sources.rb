# frozen_string_literal: true

require_relative "../../error"
require_relative "null_selection"
require_relative "../../incremental/git_diff"
require_relative "../../registry/registry"
require_relative "../../scope/file_set"

class Kimera::CLI::Run::Sources
  def initialize(errors: $stderr)
    @errors = errors
  end

  def load(options, change = Kimera::CLI::Run::NullSelection.new)
    stored = options[:registry]
    return Kimera::Registry.from_file(stored) if stored
    options.scan.build(files(options, change))
  end

  def tests(patterns, exclude)
    notice(patterns, exclude, "test")
    expand(patterns, exclude, "test", "check --tests")
    Kimera::FileSet.new(patterns, exclude: exclude).listed
  end

  private

  def files(options, change)
    patterns, exclude = options.to_h.values_at(:paths, :exclude)
    notice(patterns, exclude, "source")
    found = expand(patterns, exclude, "source", "check paths and --exclude")
    change.files(found) { |file| relative(file, options[:source_root]) }
  end

  def expand(patterns, exclude, kind, hint)
    found = Kimera::FileSet.new(patterns, exclude: exclude).files
    raise(Kimera::UsageError, "no #{kind} files matched: #{Array(patterns).join(", ")} (#{hint})") if found.empty?
    found
  end

  def notice(patterns, exclude, kind)
    Kimera::FileSet.new(patterns, exclude: exclude).unused.each do |pattern|
      @errors.puts("kimera: warning: exclude pattern matched no #{kind} files: #{pattern}")
    end
  end

  def relative(file, root)
    base = File.expand_path(root)
    Kimera::FileSet::Root.new(base).relative(file)
  end
end
