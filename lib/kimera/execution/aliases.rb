# frozen_string_literal: true

module Kimera
  module Execution
  end
end

require_relative "redefinition"

class Kimera::Execution::Aliases
  OWN = Module.instance_method(:instance_methods)
  HIDDEN = Module.instance_method(:private_instance_methods)
  LOOKUP = Module.instance_method(:instance_method)
  SINGLETON = Kernel.instance_method(:singleton_class)
  INHERITED = false

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

  module Provenance
    private

    def lookup(holder, name)
      LOOKUP.bind_call(holder, name)
    rescue NameError
      yield
    end

    def from?(method, file) = sources(method).any? { |path| alike?(path, file) }

    def sources(method) = Array(method.source_location).first(1)

    def alike?(one, other) = [one, other].map { |path| Kimera::Execution::Origin.new(path).canonical }.uniq.one?

    def compiled(method) = RubyVM::InstructionSequence.of(method)
  end

  Entry =
    Data.define(:holder, :name, :origin, :target, :body) do
      include Repointing
      include Provenance
      private(*members)
      def orphaned(file) = Orphan.new(holder, name, file, target, body, nil)
      def resolved = holder.ancestors.find { |mod| defines?(mod) }&.then { |found| with(origin: found) }
      def wrapped?(file)
        found = lookup(holder, target) { return false }
        !from?(found, file)
      end
      private
      def current = origin.instance_method(target)
      def defines?(mod)
        (mod.method_defined?(target) || mod.private_method_defined?(target)) &&
          RubyVM::InstructionSequence.of(mod.instance_method(target)).equal?(body)
      end
    end

  Orphan =
    Data.define(:holder, :name, :file, :target, :body, :fresh) do
      include Repointing
      include Provenance
      private(*members)
      def adopted(displaced)
        found = moved(displaced).fetch(0) { lookup(holder, target) { return self } }
        return self unless from?(found, file) && !compiled(found).equal?(body)
        with(fresh: found)
      end
      def reaches?(definition) = fresh == definition
      private
      def current = fresh
      def moved(displaced)
        ancestors = holder.ancestors
        displaced.flat_map { |held| held.replacing(target, ancestors) }.first(1)
      end
    end

  Tracked =
    Struct.new(:resolved, :orphans) do
      private(*members)
      def enter(entry, file)
        found = entry.resolved
        return resolved << found if found
        orphans << entry.orphaned(file) if entry.wrapped?(file)
      end
      def repoint = [resolved, orphans].each { |held| held.map!(&:repointed) }
      def witness(displaced) = orphans.map! { |orphan| orphan.adopted(displaced) }
      def reaches?(definition) = orphans.any? { |orphan| orphan.reaches?(definition) }
    end

  include Provenance

  def initialize(files, tracked = Tracked.new([], []))
    @files = files
    @tracked = tracked
  end

  def follow(&)
    capture
    again(&)
  end

  def again
    yield.tap { @tracked.repoint }
  end

  def witness(displaced = []) = @tracked.witness(displaced)

  def reaches?(definition) = @tracked.reaches?(definition)

  private

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
    files = sources(method)
    return unless renamed?(method) && files.any? { |file| watched.include?(file) }
    @tracked.enter(Entry.new(holder, method.name, nil, method.original_name, compiled(method)), files.fetch(0))
  end

  def renamed?(method) = method.original_name != method.name
end
