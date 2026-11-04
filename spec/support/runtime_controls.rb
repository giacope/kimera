# frozen_string_literal: true

# kimera's lib turns the mutation switch only through Runtime#during, which
# hands it back when its block ends; specs set it, read it and open ledgers on
# it directly, as a harness several steps away would.
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
