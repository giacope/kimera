# frozen_string_literal: true

require "tmpdir"

module Kimera
end

# A Module, so the runtime is Ractor-shareable: mutated code that runs in a
# non-main Ractor reads the active mutant (an Integer or nil) like any other
# code, and records what it reaches in the open ledgers' spill files, whose
# paths it can read.
#
# It holds all of kimera's process-wide state, and so is the one object that
# reassigns its own fields at run time.
# rubocop:disable-next Kata/FrozenState, Kata/NoSetter -- the process-wide mutation switch every thread and Ractor reads
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

  NONE = [].freeze

  attr_reader :active

  def initialize
    super
    @active = nil
    @overlaying = false
    @ledgers = NONE
    @spills = NONE
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
    @ledgers = [*@ledgers, ledger].freeze
    publish
    ledger
  end

  def stop!(ledger)
    return if @ledgers.empty?
    @ledgers = @ledgers.reject { |open| open.equal?(ledger) }.freeze
    publish
    ledger.drain!
  end

  def reset! = self.active = nil

  # Whether an overlay is re-running class bodies, so the guards it installs
  # in Rails skip declarations those bodies already made.
  def overlaying? = @overlaying

  def overlay
    @overlaying = true
    yield
  ensure
    @overlaying = false
  end

  def privatize(id, owner, name)
    hidden[Integer(id)] = Flip.new(owner, owner.instance_method(name), [])
    self
  end

  def leaks = @ledgers.map(&:leak)

  def forked!(paths)
    @ledgers = paths.map { Spill.new(it, {}) }
    publish
  end

  private

  def record(id)
    @ledgers.each { |ledger| ledger.push(id) }
  rescue Ractor::IsolationError
    remote(id)
  end

  def remote(id)
    seen = Ractor.current[:kimera_reached] ||= {}
    return if seen.key?(id)
    seen[id] = true
    @spills.each { |path| File.write(path, "#{id}\n", mode: "a") }
  end

  def publish = @spills = Ractor.make_shareable(leaks)

  def hidden = @_hidden ||= {}
end

# A visibility mutant: while it is active, the method's public names are private.
Kimera::Runtime::Flip =
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

# A forked child keeps recording what it reaches into the parent's open ledgers.
module Kimera::Runtime::Forks
  def _fork
    leaks = Kimera::RUNTIME.leaks
    super.tap { |pid| Kimera::RUNTIME.forked!(leaks) if pid.zero? && leaks.any? }
  end
end

Kimera::RUNTIME = Kimera::Runtime.new unless Kimera.const_defined?(:RUNTIME, false)
Process.singleton_class.prepend(Kimera::Runtime::Forks) unless Process.singleton_class < Kimera::Runtime::Forks
