require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "normalizes the email before validation" do
    account = Account.create!(email: "  Dave@Example.COM ", credit_cents: 0)
    assert_equal "dave@example.com", account.email
  end

  test "requires a well-formed email" do
    assert_not Account.new(email: "nobody", credit_cents: 0).valid?
    assert_not Account.new(email: "", credit_cents: 0).valid?
  end

  test "rejects negative credit" do
    assert_not Account.new(email: "x@example.com", credit_cents: -1).valid?
  end

  test "is premium with enough credit unless suspended" do
    assert accounts(:alice).premium?
    assert_not accounts(:bob).premium?
    assert_not accounts(:carol).premium?
    assert Account.new(credit_cents: 10_000).premium?
  end

  test "charges its credit" do
    alice = accounts(:alice)
    alice.charge!(1_000)
    assert_equal 49_000, alice.reload.credit_cents
  end

  test "refuses a charge above its credit" do
    assert_raises(Account::InsufficientCredit) { accounts(:bob).charge!(3_001) }
    accounts(:bob).charge!(3_000)
    assert_equal 0, accounts(:bob).reload.credit_cents
  end

  test "refuses a charge that is not positive" do
    assert_raises(ArgumentError) { accounts(:bob).charge!(0) }
  end

  test "destroys its orders with it" do
    assert_difference("Order.count", -2) { accounts(:alice).destroy }
  end
end
