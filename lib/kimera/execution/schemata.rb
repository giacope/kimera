# frozen_string_literal: true

require "stringio"
require_relative "../self_protection"
require_relative "../synthesis/overlay"
require_relative "overlay_guards"

class Kimera::Execution::Schemata
  attr_reader :skipped

  def initialize(registry, root: ".", errors: nil)
    @registry = registry
    @root = root
    @errors = errors
    @skipped = {}
  end

  class << self
    def install!
      Kimera::Execution::OverlayGuards.install!
    end

    def with_guards(&)
      Kimera::Execution::OverlayGuards.overlay(&)
    end
  end

  def overlay!
    Kimera::Execution::OverlayGuards.install!
    deferred = []
    @registry.files.flat_map { |path| load(path, deferred) } + deferred.flat_map { |path| load(path) }
  end

  private

  def load(path, deferred = nil)
    file = File.join(root, path)
    return [] unless File.file?(file)
    return [] if Kimera::SelfProtection.protected?(file)
    overlay(path, file, deferred)
  end

  def overlay(path, file, deferred)
    result = synthesize(path, file)
    return [] if result.mutant_ids.empty?
    apply(result, file)
  rescue StandardError, ScriptError, SystemExit => error
    failed(path, error, deferred)
  end

  def synthesize(path, file)
    synth.synthesize(path, File.read(file, encoding: Encoding::UTF_8))
  end

  def apply(result, file)
    silence { result.install(file) }
  end

  def failed(path, error, deferred)
    return skip(path, error) unless deferred && error.is_a?(NameError)
    deferred << path
    []
  end

  def skip(path, error)
    reason = "#{error.class}: #{error.message}"
    @skipped[path] = reason
    notice(path, reason)
    []
  end

  def notice(path, reason)
    errors.puts(
      "kimera: #{path} cannot run in warm workers — schemata setup failed " \
        "(#{reason}); its mutants are reported no_coverage"
    )
  end

  def errors = @errors || $stderr

  def root = @_root ||= File.expand_path(@root)

  def synth = @_synth ||= Kimera::Overlay.new(@registry)

  def silence(&)
    original, captured = capture
    Kimera::Execution::OverlayGuards.overlay(&).tap { original.write(captured.string) }
  ensure
    $stderr = original
  end

  def capture
    [$stderr, $stderr = StringIO.new]
  end
end
