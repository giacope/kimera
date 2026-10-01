# frozen_string_literal: true

require "stringio"
require_relative "../self_protection"
require_relative "../synthesis/body_trim"
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

  def overlay!
    Kimera::Execution::OverlayGuards.install!
    loaded = weave(@registry.files)
    (loaded + weave(unresolved)).tap { announce }
  end

  private

  def weave(paths) = paths.flat_map { |path| load(path) }

  def unresolved
    @skipped.keys.select { |path| @skipped[path].start_with?("NameError:") }.each { |path| @skipped.delete(path) }
  end

  def announce
    @skipped.each do |path, reason|
      notice(path, reason)
      @registry.at(path).select(&:safe?).each { |point| point.unmutatable!("schemata setup failed (#{reason})") }
    end
  end

  def load(path)
    file = File.join(root, path)
    return [] unless File.file?(file)
    return [] if Kimera::SelfProtection.protected?(file)
    overlay(path, file)
  end

  def overlay(path, file)
    result = synthesize(path, file)
    return [] if result.mutant_ids.empty?
    apply(result, file).tap { preempt(file) }
  rescue StandardError, ScriptError, SystemExit => error
    skip(path, "#{error.class}: #{error.message}")
  end

  def preempt(file) = $LOADED_FEATURES.concat([file, File.realpath(file)].uniq - $LOADED_FEATURES)

  def synthesize(path, file)
    source = File.read(file, encoding: Encoding::UTF_8)
    synth.synthesize(path, Kimera::BodyTrim.trim(file, source, @registry.at(path).select(&:safe?).map(&:location)))
  end

  def apply(result, file)
    silence { result.install(file) }
  end

  def skip(path, reason)
    @skipped[path] = reason
    []
  end

  def notice(path, reason)
    errors.puts(
      "kimera: #{path} cannot run in warm workers — schemata setup failed " \
        "(#{reason}); its mutants are reported unmutatable"
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
