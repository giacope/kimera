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
    options = parse(argv)
    pid_file(options[:pidfile]) { cycle(options).call }
  rescue Kimera::Error => error
    @errors.puts("kimera: #{error.message}")
    1
  end

  private

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
    changed = options[:since] ? Kimera::CLI::Run::Sources.changed(options) : nil
    registry = Kimera::CLI::Run::Sources.new(errors: @errors).load(options, changed)
    Kimera::CLI::Run::Cycle.new(options, registry, changed, digest: digest(options))
  end

  def digest(options = {})
    narration = options.fetch(:format, "text") == "text" ? @io : @errors
    emission = Kimera::CLI::Run::Emission.new(io: narration, output: @io, **options.slice(:color, :quiet))
    Kimera::CLI::Run::Digest.new(io: narration, errors: @errors, emission: emission)
  end
end
