require_relative "sequence"

module Ticket
  def self.issue(priority)
    n = Sequence.next!
    prefix = priority > 2 ? "HI" : "LO"
    format("%s-%03d", prefix, n * 10 + priority)
  end
end
