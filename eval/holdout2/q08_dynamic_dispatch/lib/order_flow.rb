# frozen_string_literal: true

# Order state machine. Public event methods forward their own name
# (__method__) to #fire, which looks up guards and hooks by building method
# names and calling them with send.
class OrderFlow
  class InvalidTransition < StandardError; end

  TRANSITIONS = {
    pending: { pay: :paid, cancel: :cancelled },
    paid: { ship: :shipped, refund: :refunded },
    shipped: { deliver: :delivered, lose: :lost },
    lost: { refund: :refunded }
  }.freeze
  EVENTS = TRANSITIONS.values.flat_map(&:keys).uniq.freeze
  FINAL = %i[cancelled refunded delivered].freeze

  class << self
    attr_accessor :strict, :refund_window_days

    def journal
      @journal ||= []
    end

    # "pay:120 ship deliver" => runs each event in turn, stops at the first refusal.
    def replay(total, script)
      order = new(total)
      script.split.each do |step|
        name, arg = step.split(":", 2)
        raise ArgumentError, "unknown event #{name}" unless EVENTS.include?(name.to_sym)

        args = arg ? [Integer(arg)] : []
        break unless order.public_send(name, *args)
      end
      order
    end
  end
  self.refund_window_days = 14

  attr_reader :state, :total, :paid_amount

  def initialize(total)
    @total = total
    @state = :pending
    @paid_amount = 0
  end

  def pay(amount) = fire(__method__, amount)
  def cancel = fire(__method__)
  def ship = fire(__method__)
  def deliver = fire(__method__)
  def lose = fire(__method__)
  def refund(days_since_payment) = fire(__method__, days_since_payment)

  def final?
    FINAL.include?(state)
  end

  def available_events
    TRANSITIONS.fetch(state, {}).keys
  end

  def change_due
    paid_amount - total
  end

  private

  def fire(event, *args)
    target = TRANSITIONS.dig(state, event)
    return reject(event, "cannot #{event} when #{state}") unless target

    guard = :"can_#{event}?"
    return reject(event, "#{guard} refused") if respond_to?(guard, true) && !send(guard, *args)

    hook = :"on_#{event}"
    send(hook, *args) if respond_to?(hook, true)
    @state = target
    self.class.journal << [object_id, event, target]
    true
  end

  def reject(event, reason)
    raise InvalidTransition, reason if self.class.strict

    self.class.journal << [object_id, event, :rejected]
    false
  end

  def can_pay?(amount)
    amount >= total
  end

  def on_pay(amount)
    @paid_amount = amount
  end

  def can_refund?(days)
    state == :lost || days <= self.class.refund_window_days
  end

  def on_refund(_days)
    @paid_amount = 0
  end
end
