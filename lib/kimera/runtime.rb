# frozen_string_literal: true

require "tmpdir"

module Kimera
end

class Kimera::Runtime
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

  module Forks
    def _fork
      leaks = Kimera::RUNTIME.leaks
      super.tap { |pid| Kimera::RUNTIME.forked!(leaks) if pid.zero? && leaks }
    end
  end

  attr_reader :active

  def initialize
    @active = nil
    @ledgers = nil
  end

  def active=(id)
    @active = id && Integer(id)
  end

  def active?(id)
    @ledgers&.each { |ledger| ledger.push(id) }
    @active == id
  end

  def start!
    ledger = Ledger.new({})
    (@ledgers ||= []).push(ledger)
    ledger
  end

  def stop!(ledger)
    open = @ledgers
    return unless open
    open.delete_if { |l| l.equal?(ledger) }
    @ledgers = nil if open.empty?
    ledger.drain!
  end

  def reset!
    @active = nil
  end

  def leaks = @ledgers&.map(&:leak)

  def forked!(paths)
    @ledgers = paths.map { Spill.new(it, {}) }
  end
end

Kimera::RUNTIME = Kimera::Runtime.new unless Kimera.const_defined?(:RUNTIME, false)
Process.singleton_class.prepend(Kimera::Runtime::Forks) unless Process.singleton_class < Kimera::Runtime::Forks
