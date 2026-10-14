require_relative "../lib/widget"

RSpec.describe Widget do
  it("is plain above 1") { expect([Widget.new(2).plain?, Widget.new(1).plain?]).to eq([true, false]) }
  it("is tiny below 3 but not 0") { expect([1, 2, 3, 0].map { Widget.new(_1).tiny? }).to eq([true, true, false, false]) }
  it("is huge from 500, or at -1") { expect([500, 499, -1, 0].map { Widget.new(_1).huge? }).to eq([true, false, true, false]) }
  it("validates sizes") { expect([3, 0, -2, "3"].map { Widget.valid_size?(_1) }).to eq([true, false, false, false]) }
  it("knows odd sizes") { expect([3, 4].map { Widget.new(_1).odd_sized? }).to eq([true, false]) }
  it("knows even sizes") { expect([3, 4].map { Widget.new(_1).even_sized? }).to eq([false, true]) }
  it("is small below 10") { expect([9, 10].map { Widget.new(_1).small? }).to eq([true, false]) }
  it("is large above 100") { expect([101, 100].map { Widget.new(_1).large? }).to eq([true, false]) }
  it("is round at multiples of 10") { expect([20, 21].map { Widget.new(_1).round? }).to eq([true, false]) }
  it("is sane between 1 and 999") { expect([1, 0, 999, 1000].map { Widget.new(_1).sane? }).to eq([true, false, true, false]) }
  it("doubles limits above 10") { expect(Widget.limit).to eq(100) }
end
