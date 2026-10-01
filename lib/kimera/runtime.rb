# frozen_string_literal: true

module Kimera
end

class Kimera::Runtime
  SOURCE_PATH = File.expand_path(__FILE__)

  Ledger =
    Struct.new(:ids) do
      def push(id) = ids.push(id)

      def clear = ids.clear

      def empty? = ids.empty?

      def drain!
        touched = ids.uniq
        ids.clear
        touched
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
    ledger = Ledger.new([])
    (@ledgers ||= []).push(ledger)
    ledger
  end

  def stop!(ledger)
    open = @ledgers
    return unless open
    open.delete_if { |l| l.equal?(ledger) }
    @ledgers = nil if open.empty?
  end

  def reset!
    @active = nil
  end
end

Kimera::RUNTIME = Kimera::Runtime.new

MutantRuntime = Kimera::RUNTIME unless defined?(MutantRuntime)
