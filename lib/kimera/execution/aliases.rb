# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Aliases
  Entry = Data.define(:holder, :name, :origin, :target, :body)
  OWN = Module.instance_method(:instance_methods)
  HIDDEN = Module.instance_method(:private_instance_methods)
  LOOKUP = Module.instance_method(:instance_method)
  SINGLETON = Kernel.instance_method(:singleton_class)

  def initialize(files)
    @files = files
    @entries = []
  end

  def follow(&)
    capture
    again(&)
  end

  def again
    yield.tap { @entries.map! { |entry| repoint(entry) } }
  end

  private

  def watched = @_watched ||= @files.flat_map { |file| [file, *real(file)] }

  def real(file) = File.exist?(file) ? [File.realpath(file)] : []

  def capture
    ObjectSpace.each_object(Module) { |mod| [mod, SINGLETON.bind_call(mod)].each { |holder| scan(holder) } }
  end

  def scan(holder)
    names = OWN.bind_call(holder, false) + HIDDEN.bind_call(holder, false)
    names.each { |name| track(holder, LOOKUP.bind_call(holder, name)) }
  end

  def track(holder, method)
    return if method.original_name == method.name || !watched.include?(method.source_location&.first)
    entry = Entry.new(holder, method.name, nil, method.original_name, compiled(method))
    origin = holder.ancestors.find { |mod| resolves?(mod, entry.target, entry.body) }
    @entries << entry.with(origin: origin) if origin
  end

  def resolves?(mod, target, body)
    (mod.method_defined?(target) || mod.private_method_defined?(target)) &&
      compiled(mod.instance_method(target)).equal?(body)
  end

  def repoint(entry)
    fresh = entry.origin.instance_method(entry.target)
    return entry unless stale?(entry, fresh)
    redefine(entry.holder, entry.name, fresh)
    entry.with(body: compiled(fresh))
  end

  def stale?(entry, fresh)
    entry => { holder:, name:, body: }
    compiled(holder.instance_method(name)).equal?(body) && !compiled(fresh).equal?(body)
  end

  def redefine(holder, name, fresh)
    visibility = visibility(holder, name)
    holder.define_method(name, fresh)
    holder.__send__(visibility, name)
  end

  def visibility(holder, name)
    return :private if holder.private_method_defined?(name)
    holder.protected_method_defined?(name) ? :protected : :public
  end

  def compiled(method) = RubyVM::InstructionSequence.of(method)
end
