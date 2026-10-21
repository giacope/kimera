# frozen_string_literal: true

module Kimera
  module Execution
  end
end

require_relative "redefinition"

class Kimera::Execution::Aliases
  Entry =
    Data.define(:holder, :name, :origin, :target, :body) do
      def current = origin.instance_method(target)
    end
  Orphan =
    Data.define(:holder, :name, :file, :target, :body, :fresh) do
      def current = fresh
    end
  OWN = Module.instance_method(:instance_methods)
  HIDDEN = Module.instance_method(:private_instance_methods)
  LOOKUP = Module.instance_method(:instance_method)
  SINGLETON = Kernel.instance_method(:singleton_class)
  INHERITED = false

  def initialize(files)
    @files = files
    @entries = []
    @orphans = []
  end

  def follow(&)
    capture
    again(&)
  end

  def again
    yield.tap { [@entries, @orphans].each { |held| held.map! { |entry| repoint(entry) } } }
  end

  def witness(displaced = [])
    @orphans.map! { |orphan| adopt(orphan, displaced) }
  end

  private

  def watched = @_watched ||= @files.flat_map { |file| [file, *real(file)] }

  def real(file) = File.exist?(file) ? [File.realpath(file)] : []

  def capture
    ObjectSpace.each_object(Module) { |mod| [mod, SINGLETON.bind_call(mod)].each { |holder| scan(holder) } }
  end

  def scan(holder)
    names = OWN.bind_call(holder, INHERITED) + HIDDEN.bind_call(holder, INHERITED)
    names.each { |name| track(holder, LOOKUP.bind_call(holder, name)) }
  end

  def track(holder, method)
    file = source(method)
    return unless renamed?(method) && watched.include?(file)
    enter(Entry.new(holder, method.name, nil, method.original_name, compiled(method)), file)
  end

  def enter(entry, file)
    origin = entry.holder.ancestors.find { |mod| resolves?(mod, entry.target, entry.body) }
    return @entries << entry.with(origin: origin) if origin
    @orphans << orphan(entry, file) if wrapped?(entry, file)
  end

  def orphan(entry, file) = Orphan.new(entry.holder, entry.name, file, entry.target, entry.body, nil)

  def wrapped?(entry, file)
    found = lookup(entry.holder, entry.target)
    found && !alike?(source(found), file)
  end

  def adopt(orphan, displaced)
    found = moved(orphan, displaced) || lookup(orphan.holder, orphan.target)
    return orphan unless found && alike?(source(found), orphan.file) && !compiled(found).equal?(orphan.body)
    orphan.with(fresh: found)
  end

  def moved(orphan, displaced)
    ancestors = orphan.holder.ancestors
    displaced.find { |held| held.name == orphan.target && ancestors.include?(held.holder) }&.definition
  end

  def lookup(holder, name)
    LOOKUP.bind_call(holder, name)
  rescue NameError
    nil
  end

  def source(method) = method.source_location&.first

  def alike?(one, other) = [one, other].map { |path| Kimera::Execution::Origin.new(path).canonical }.uniq.one?

  def renamed?(method) = method.original_name != method.name

  def resolves?(mod, target, body)
    (mod.method_defined?(target) || mod.private_method_defined?(target)) &&
      compiled(mod.instance_method(target)).equal?(body)
  end

  def repoint(entry)
    fresh = entry.current
    return entry unless fresh && stale?(entry, fresh)
    Kimera::Execution::Redefinition.new(entry.holder, entry.name).redefine(fresh)
    entry.with(body: compiled(fresh))
  end

  def stale?(entry, fresh)
    entry => { holder:, name:, body: }
    compiled(holder.instance_method(name)).equal?(body) && !compiled(fresh).equal?(body)
  end

  def compiled(method) = RubyVM::InstructionSequence.of(method)
end
