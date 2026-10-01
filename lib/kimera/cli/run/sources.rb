# frozen_string_literal: true

require_relative "../../error"
require_relative "../../incremental/git_diff"
require_relative "../../operators"
require_relative "../../registry/builder"
require_relative "../../registry/registry"
require_relative "../../scope/file_set"

class Kimera::CLI::Run::Sources
  def initialize(errors: $stderr)
    @errors = errors
  end

  def load(options, changed = nil)
    stored = options[:registry]
    return Kimera::Registry.from_file(stored) if stored
    build(options, files(options, changed))
  end

  def files(options, changed)
    found = expand(options[:paths], options[:exclude], "source", "check paths and --exclude")
    return found unless changed
    root = File.expand_path(options[:source_root])
    found.select { |file| changed.key?(Kimera::FileSet.relative(file, root)) }
  end

  def expand(patterns, exclude, kind, hint)
    notice(patterns, exclude, kind)
    found = Kimera::FileSet.expand(patterns, exclude: exclude)
    raise(Kimera::UsageError, "no #{kind} files matched: #{Array(patterns).join(", ")} (#{hint})") if found.empty?
    found
  end

  def notice(patterns, exclude, kind)
    Kimera::FileSet.unused(patterns, exclude).each do |pattern|
      @errors.puts("kimera: warning: exclude pattern matched no #{kind} files: #{pattern}")
    end
  end

  private

  def build(options, files)
    Kimera::RegistryScan.new(
      operators: Kimera::Operators.build(keys: options[:operators]),
      root: options[:source_root],
      shielded: !options[:isolated]
    ).build(files)
  end
end
