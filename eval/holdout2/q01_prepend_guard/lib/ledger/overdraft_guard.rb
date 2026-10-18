# frozen_string_literal: true

module Ledger
  # Prepended into Account when this file loads: lets a withdrawal take the
  # balance below zero, down to a configurable limit.
  module OverdraftGuard
    DEFAULT_LIMIT = 5_000

    class << self
      attr_writer :limit

      def limit
        @limit ||= DEFAULT_LIMIT
      end
    end

    def withdraw(amount)
      total = amount + fee_for(amount)
      return super if total <= balance || !amount.positive?

      shortfall = total - balance
      if shortfall > OverdraftGuard.limit
        raise InsufficientFunds, "overdraft of #{shortfall} exceeds #{OverdraftGuard.limit}"
      end

      @balance -= total
      history << [:overdraft, total]
      @balance
    end

    def headroom
      balance + OverdraftGuard.limit
    end
  end

  Account.prepend(OverdraftGuard)
end
