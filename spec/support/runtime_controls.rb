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

  def ledgers = @sink.fan

  def leaks = ledgers.map(&:spilled)

  def contained
    flips = hidden.to_h.fetch(:flips)
    kept = flips.dup
    yield
  ensure
    flips.replace(kept)
  end
end

Kimera::Runtime.include(RuntimeControls)
