# frozen_string_literal: true

require_relative "ledger/account"
require_relative "ledger/overdraft_guard"

module Ledger
  # Optional wrapper, prepended at runtime by Ledger.enable_audit!; once
  # prepended it stays for the rest of the process.
  module Audit
    def self.log
      @log ||= []
    end

    def deposit(amount)
      result = super
      Audit.log << "#{owner} +#{amount} => #{result}"
      result
    end

    def withdraw(amount)
      before = balance
      result = super
      Audit.log << "#{owner} -#{before - result} => #{result}"
      result
    end
  end

  def self.enable_audit!
    return false if Account.ancestors.include?(Audit)

    Account.prepend(Audit)
    true
  end
end
