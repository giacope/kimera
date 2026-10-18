# frozen_string_literal: true

module Ledger
  class InsufficientFunds < StandardError; end

  # A cash account that keeps balances in cents.
  class Account
    FEE_RATE = 0.015
    MIN_FEE = 25
    FEE_THRESHOLD = 1_000

    attr_reader :owner, :balance, :history

    def initialize(owner, balance: 0)
      raise ArgumentError, "negative opening balance" if balance.negative?

      @owner = owner
      @balance = balance
      @history = []
    end

    def deposit(amount)
      raise ArgumentError, "amount must be positive" unless amount.positive?

      @balance += amount
      @history << [:deposit, amount]
      @balance
    end

    def withdraw(amount)
      raise ArgumentError, "amount must be positive" unless amount.positive?

      total = amount + fee_for(amount)
      raise InsufficientFunds, "need #{total}, have #{@balance}" if total > @balance

      @balance -= total
      @history << [:withdraw, total]
      @balance
    end

    def fee_for(amount)
      return 0 if amount < FEE_THRESHOLD

      [(amount * FEE_RATE).round, MIN_FEE].max
    end

    def transfer(to, amount)
      withdraw(amount)
      to.deposit(amount)
      [balance, to.balance]
    end

    def overdrawn?
      balance.negative?
    end
  end
end
