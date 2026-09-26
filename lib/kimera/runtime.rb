# frozen_string_literal: true

module Kimera
  module Runtime
    SOURCE_PATH = File.expand_path(__FILE__)

    class << self
      attr_reader :active

      def active=(id)
        @active = id && Integer(id)
      end

      def active?(id)
        @ledgers&.each { |ledger| ledger.push(id) }
        @active == id
      end

      def start!
        ledger = []
        (@ledgers ||= []).push(ledger)
        ledger
      end

      def drain!(ledger)
        touched = ledger.uniq
        clear!(ledger)
        touched
      end

      def clear!(ledger)
        ledger.clear
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

    reset!
  end
end

MutantRuntime = Kimera::Runtime unless defined?(MutantRuntime)
