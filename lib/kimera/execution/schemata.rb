# frozen_string_literal: true

require "stringio"
require_relative "../self_protection"
require_relative "../synthesis/body_trim"
require_relative "../synthesis/overlay"
require_relative "aliases"
require_relative "block_methods"
require_relative "bound_lambdas"
require_relative "definitions"
require_relative "overrides"
require_relative "overlay_guards"
require_relative "pending_autoload"

class Kimera::Execution::Schemata
  Woven = Struct.new(:skipped)

  def initialize(registry, root: ".", errors: nil, loaded: proc { true })
    @registry = registry
    @root = root
    @errors = errors
    @loaded = loaded
  end

  def skipped = woven.skipped

  def overlay!
    Kimera::Execution::OverlayGuards.new.install!
    aliases.follow { weave(reachable) + weave(unresolved) }.tap { announce }
  end

  def aliases = @_aliases ||= Kimera::Execution::Aliases.new(@registry.files.map { |path| File.join(root, path) })

  private

  def woven = @_woven ||= Woven.new({})

  def reachable
    unasked = @registry.files.reject { |path| asked?(path) }
    failures = unasked.to_h { |path| [path, fire(path)] }
    shut = unasked.reject { |path| required?(path) || definitions?(path) }
    shut.each { |path| unload(path, failures[path]) }
    @registry.files - shut
  end

  def asked?(path) = @loaded.call(path) || !File.file?(File.join(root, path))

  def fire(path)
    Kimera::Execution::PendingAutoload.new(File.join(root, path)).fire!
    nil
  rescue StandardError, ScriptError => error
    "#{error.class}: #{error.message}"
  end

  def required?(path)
    file = File.join(root, path)
    $LOADED_FEATURES.include?(file) || $LOADED_FEATURES.include?(File.realpath(file))
  end

  def definitions?(path)
    Kimera::Execution::Definitions.new(File.read(File.join(root, path), encoding: Encoding::UTF_8)).only?
  end

  def unload(path, failure) = @registry.at(path).select(&:safe?).each { |point| point.unloaded!(failure) }

  def weave(paths) = paths.flat_map { |path| load(path) }

  def unresolved
    skipped.keys.select { |path| skipped[path].start_with?("NameError:") }.each { |path| skipped.delete(path) }
  end

  def announce
    skipped.each do |path, reason|
      next unload(path, reason) unless @loaded.call(path)
      notice(path, reason)
      @registry.at(path).select(&:safe?).each { |point| point.unmutatable!("schemata setup failed (#{reason})") }
    end
  end

  def load(path)
    file = File.join(root, path)
    return [] unless File.file?(file)
    return [] if Kimera::SelfProtection.new(file).protected?
    Kimera::Execution::BoundLambdas.new(@registry, root).hold!(path)
    overlay(path, file)
  end

  def overlay(path, file)
    loaded = trimmed(path, file)
    result = synth.synthesize(path, loaded)
    return [] if result.mutant_ids.empty?
    blocks = Kimera::Execution::BlockMethods.new(file, loaded, result.source, locations(path))
    apply(result, file, blocks).tap { preempt(file) }
  rescue StandardError, ScriptError, SystemExit => error
    skip(path, "#{error.class}: #{error.message}")
  end

  def preempt(file) = $LOADED_FEATURES.concat([file, File.realpath(file)].uniq - $LOADED_FEATURES)

  def trimmed(path, file)
    Kimera::BodyTrim.new(File.read(file, encoding: Encoding::UTF_8), locations(path)).trim(file)
  end

  def locations(path) = @registry.at(path).select(&:safe?).map(&:location)

  def apply(result, file, blocks)
    overrides = Kimera::Execution::Overrides.new(file, result.source)
    installed, displaced = silence { overrides.keep { blocks.adopt { result.install(file) } } }
    aliases.witness(displaced)
    displaced.reject { |held| aliases.reaches?(held.definition) }.each { it.revisit!(@registry.at(result.file)) }
    installed
  end

  def skip(path, reason)
    skipped[path] = reason
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
    Kimera::Execution::OverlayGuards.new.overlay(&).tap { original.write(captured.string) }
  ensure
    $stderr = original
  end

  def capture
    [$stderr, $stderr = StringIO.new]
  end
end
