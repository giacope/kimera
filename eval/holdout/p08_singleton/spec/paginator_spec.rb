require_relative "../lib/paginator"

RSpec.describe Paginator do
  it "counts pages" do
    expect(Paginator.new(25).pages).to eq(3)
    expect(Paginator.new(10).pages).to eq(1)
    expect(Paginator.new(11).pages).to eq(2)
    expect(Paginator.new(0).pages).to eq(0)
  end

  it "caps the total" do
    expect(Paginator.new(100).pages).to eq(3)
  end

  it "computes ranges" do
    expect(Paginator.new(25).range(3)).to eq(20...25)
    expect(Paginator.new(30).range(1)).to eq(0...10)
    expect(Paginator.new(100).range(3)).to eq(20...30)
  end

  it "rejects out-of-range pages" do
    expect { Paginator.new(25).range(0) }.to raise_error(ArgumentError)
    expect { Paginator.new(25).range(4) }.to raise_error(ArgumentError)
  end
end
