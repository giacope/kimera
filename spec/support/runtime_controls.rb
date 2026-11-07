# frozen_string_literal: true

module RuntimeControls
  def active = @active

  def active=(id)
    choose(id)
  end

  def reset! = choose(nil)

  def start! = Kimera::Runtime::Ledger.new.tap { opened([it]) }

  def stop!(ledger)
    closed([ledger])
    ledger.drain!
  end

  def leaks = @ledgers.map(&:spilled)
end

Kimera::Runtime.include(RuntimeControls)
