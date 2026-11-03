# frozen_string_literal: true

require "fileutils"
require_relative "../error"
require_relative "../plugins"
require_relative "../work_tree"

module Kimera
end

class Kimera::CLI
end

class Kimera::CLI::Run
end

require_relative "run/arguments"
require_relative "run/bench"
require_relative "run/cycle"
require_relative "run/digest"
require_relative "run/options"
require_relative "run/sources"
require_relative "run/streams"
require_relative "outcome"

class Kimera::CLI::Run
  def initialize(
    io: $stdout, errors: $stderr, arguments: Kimera::CLI::Run::Arguments.new, bench: Kimera::CLI::Run::Bench.new
  )
    @io = io
    @errors = errors
    @arguments = arguments
    @bench = bench
  end

  def run(argv, streams = Kimera::CLI::Run::Streams.new)
    options = parse(argv)
    return perform(options) unless machine?(options, streams)
    report = @io.dup.tap { |copy| copy.sync = true }
    streams.divert
    self.class.new(io: report, errors: @errors, bench: @bench).perform(options)
  rescue Kimera::Error => error
    Kimera::CLI::Outcome::Failed.new(1, "kimera: #{error.message}")
  end

  protected

  def perform(options) = pid_file(options[:pidfile]) { guarded(options) { cycle(options) } }

  private

  def machine?(options, streams)
    options.to_h.fetch(:format, "text") != "text" && streams.standard?(@io) && @io.is_a?(IO)
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

  def guarded(options, &)
    ignored = options.to_h.values_at(:report, :session, :pidfile, :log)
    code, warning = Kimera::WorkTree.new(options[:source_root] || ".", ignored: ignored).watch(&)
    warning ? Kimera::CLI::Outcome::Failed.new(1, warning) : Kimera::CLI::Outcome::Ended.new(code)
  end

  def parse(argv) = @arguments.parse(argv)

  def cycle(options)
    options.plugins.load!
    change = options.change(@bench)
    registry = Kimera::CLI::Run::Sources.new(errors: @errors).load(options, change)
    built(options, change.narrowed(registry)).call(change, @bench)
  end

  def built(options, registry)
    Kimera::CLI::Run::Cycle.new(
      options, registry, digest: digest(options), alerts: Kimera::CLI::Run::Alerts.new(errors: @errors)
    )
  end

  def digest(options = {})
    narration = options.to_h.fetch(:format, "text") == "text" ? @io : @errors
    emission = Kimera::CLI::Run::Emission.new(io: narration, output: @io, **options.to_h.slice(:color, :quiet))
    Kimera::CLI::Run::Digest.new(io: narration, emission: emission)
  end
end
