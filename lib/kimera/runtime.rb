# frozen_string_literal: true

require "tmpdir"

module Kimera
end

# A Module, so the runtime is Ractor-shareable: mutated code that runs in a
# non-main Ractor reads the active mutant (an Integer or nil) like any other
# code, and records what it reaches in the open ledgers' spill files, whose
# paths it can read.
class Kimera::Runtime < Module
  SOURCE_PATH = File.expand_path(__FILE__)

  Ledger =
    Struct.new(:ids, :spill) do
      def push(id)
        ids[id] = true
      end

      def drain!
        absorb
        touched = ids.keys
        ids.clear
        touched
      end

      def leak = self.spill ||= File.join(Dir.tmpdir, "kimera-ledger-#{Process.pid}-#{object_id}-#{rand(1 << 32)}")

      def absorb
        return unless spill && File.exist?(spill)
        File.foreach(spill) { |line| ids[Integer(line)] = true }
        File.delete(spill)
      end
    end

  Spill =
    Struct.new(:leak, :ids) do
      def push(id)
        return if ids.key?(id)
        ids[id] = true
        File.write(leak, "#{id}\n", mode: "a")
      end
    end

  Flip =
    Struct.new(:owner, :definition, :names) do
      def conceal
        self.names = owner.public_instance_methods(false).select { |name| owner.instance_method(name) == definition }
        expose(:private)
      end

      def reveal
        expose(:public)
        names.clear
      end

      def expose(visibility)
        names.each { |name| owner.__send__(visibility, name) }
        owner.clear_action_methods! if owner.respond_to?(:clear_action_methods!)
      end
    end

  module Forks
    def _fork
      leaks = Kimera::RUNTIME.leaks
      super.tap { |pid| Kimera::RUNTIME.forked!(leaks) if pid.zero? && leaks }
    end
  end

  attr_reader :active

  def initialize
    super
    @active = nil
    @ledgers = nil
  end

  def active=(id)
    flips = hidden
    flips[@active]&.reveal
    @active = id && Integer(id)
    flips[@active]&.conceal
  end

  def active?(id)
    record(id)
    @active == id
  end

  def start!
    ledger = Ledger.new({})
    (@ledgers ||= []).push(ledger)
    publish
    ledger
  end

  def stop!(ledger)
    open = @ledgers
    return unless open
    open.delete_if { |l| l.equal?(ledger) }
    @ledgers = nil if open.empty?
    publish
    ledger.drain!
  end

  def reset!
    self.active = nil
  end

  def privatize(id, owner, name)
    hidden[Integer(id)] = Flip.new(owner, owner.instance_method(name), [])
    self
  end

  def leaks = @ledgers&.map(&:leak)

  def forked!(paths)
    @ledgers = paths.map { Spill.new(it, {}) }
    publish
  end

  private

  def record(id)
    @ledgers&.each { |ledger| ledger.push(id) }
  rescue Ractor::IsolationError
    remote(id)
  end

  def remote(id)
    seen = Ractor.current[:kimera_reached] ||= {}
    return if seen.key?(id)
    seen[id] = true
    @spills&.each { |path| File.write(path, "#{id}\n", mode: "a") }
  end

  def publish = @spills = Ractor.make_shareable(@ledgers&.map(&:leak))

  def hidden = @_hidden ||= {}
end

Kimera::RUNTIME = Kimera::Runtime.new unless Kimera.const_defined?(:RUNTIME, false)
Process.singleton_class.prepend(Kimera::Runtime::Forks) unless Process.singleton_class < Kimera::Runtime::Forks
