# frozen_string_literal: true

require "fileutils"
require_relative "../error"
require_relative "../plugins"

module Kimera
end

class Kimera::CLI
end

class Kimera::CLI::Run
end

require_relative "run/arguments"
require_relative "run/cycle"
require_relative "run/digest"
require_relative "run/options"
require_relative "run/sources"

class Kimera::CLI::Run
  include Kimera::CLI::RunOptions

  def initialize(io: $stdout, errors: $stderr)
    @io = io
    @errors = errors
  end

  def run(argv)
    options = parse(argv).tap { |parsed| detach if machine?(parsed) }
    pid_file(options[:pidfile]) { cycle(options).call }
  rescue Kimera::Error => error
    @errors.puts("kimera: #{error.message}")
    1
  end

  private

  def machine?(options) = options.fetch(:format, "text") != "text" && @io.equal?($stdout) && @io.is_a?(IO)

  def detach
    @io = @io.dup.tap { |report| report.sync = true }
    $stdout.reopen($stderr)
  end

  def pid_file(path, &)
    return yield unless path
    File.write(path, "#{Process.pid}\n")
    held(path, &)
  end

  def held(path)
    yield
  ensure
    FileUtils.rm_f(path)
  end

  def parse(argv) = Kimera::CLI::Run::Arguments.new.parse(argv)

  def cycle(options)
    Kimera::Plugins.load!(options[:require], root: options[:source_root])
    changed = changes(options)
    registry = Kimera::CLI::Run::Sources.new(errors: @errors).load(options, changed)
    Kimera::CLI::Run::Cycle.new(options, registry, changed, digest: digest(options))
  end

  def changes(options)
    since = options[:since]
    Kimera::Incremental::GitDiff.new(since: since, root: options[:source_root]).lines if since
  end

  def digest(options = {})
    narration = options.fetch(:format, "text") == "text" ? @io : @errors
    emission = Kimera::CLI::Run::Emission.new(io: narration, output: @io, **options.slice(:color, :quiet))
    Kimera::CLI::Run::Digest.new(io: narration, errors: @errors, emission: emission)
  end
end
