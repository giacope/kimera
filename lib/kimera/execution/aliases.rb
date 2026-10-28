# frozen_string_literal: true

module Kimera
  module Execution
  end
end

require_relative "redefinition"

class Kimera::Execution::Aliases
  module Repointing
    def repointed
      fresh = current
      return self unless fresh && stale?(fresh)
      Kimera::Execution::Redefinition.new(holder, name).redefine(fresh)
      with(body: RubyVM::InstructionSequence.of(fresh))
    end

    private

    def stale?(fresh)
      RubyVM::InstructionSequence.of(holder.instance_method(name)).equal?(body) &&
        !RubyVM::InstructionSequence.of(fresh).equal?(body)
    end
  end

  Entry = Data.define(:holder, :name, :origin, :target, :body)

  class Entry
    include Repointing

    def current = origin.instance_method(target)

    def orphaned(file) = Kimera::Execution::Aliases::Orphan.new(holder, name, file, target, body, nil)

    def resolved = holder.ancestors.find { |mod| defines?(mod) }&.then { |found| with(origin: found) }

    private

    def defines?(mod)
      (mod.method_defined?(target) || mod.private_method_defined?(target)) &&
        RubyVM::InstructionSequence.of(mod.instance_method(target)).equal?(body)
    end
  end

  Orphan =
    Data.define(:holder, :name, :file, :target, :body, :fresh) do
      include Repointing
      def current = fresh
    end
  OWN = Module.instance_method(:instance_methods)
  HIDDEN = Module.instance_method(:private_instance_methods)
  LOOKUP = Module.instance_method(:instance_method)
  SINGLETON = Kernel.instance_method(:singleton_class)
  INHERITED = false

  Tracked = Struct.new(:resolved, :orphans)

  def initialize(files)
    @files = files
  end

  def follow(&)
    capture
    again(&)
  end

  def again
    yield.tap { tracked.each { |held| held.map!(&:repointed) } }
  end

  def witness(displaced = [])
    tracked.orphans.map! { |orphan| adopt(orphan, displaced) }
  end

  def reaches?(definition) = tracked.orphans.any? { |orphan| orphan.fresh == definition }

  private

  def tracked = @_tracked ||= Tracked.new([], [])

  def watched
    @_watched ||= @files.flat_map { |file| [file, *(File.realpath(file) if File.exist?(file))] }
  end

  def capture
    ObjectSpace.each_object(Module) do |mod|
      [mod, SINGLETON.bind_call(mod)].each do |holder|
        names = OWN.bind_call(holder, INHERITED) + HIDDEN.bind_call(holder, INHERITED)
        names.each { |name| track(holder, LOOKUP.bind_call(holder, name)) }
      end
    end
  end

  def track(holder, method)
    file = source(method)
    return unless renamed?(method) && watched.include?(file)
    enter(Entry.new(holder, method.name, nil, method.original_name, compiled(method)), file)
  end

  def enter(entry, file)
    resolved = entry.resolved
    return tracked.resolved << resolved if resolved
    tracked.orphans << entry.orphaned(file) if wrapped?(entry, file)
  end

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

  def compiled(method) = RubyVM::InstructionSequence.of(method)
end
