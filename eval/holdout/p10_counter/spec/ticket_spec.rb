require_relative "../lib/ticket"

RSpec.describe Ticket do
  def num(ticket) = ticket.split("-").last.to_i

  it "numbers consecutive tickets ten apart" do
    a = Ticket.issue(1)
    b = Ticket.issue(1)
    expect(num(b) - num(a)).to eq(10)
    expect(num(a) % 10).to eq(1)
  end

  it "prefixes by priority" do
    expect(Ticket.issue(3)).to match(/\AHI-\d*3\z/)
    expect(Ticket.issue(2)).to match(/\ALO-\d*2\z/)
  end

  it "counts upwards from one" do
    x = Sequence.next!
    y = Sequence.next!
    expect(y).to eq(x + 1)
    expect(x).to be >= 1
  end

  it "pads to at least three digits" do
    expect(Ticket.issue(1)).to match(/\ALO-\d{3,}\z/)
  end
end
