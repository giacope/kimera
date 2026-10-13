require "test_helper"

class OrderTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "totals a small order at list price" do
    order = accounts(:bob).orders.create!(quantity: 1)
    assert_equal 2_500, order.total_cents
  end

  test "discounts ten or more by a fifth" do
    assert_equal 0.2, Order.new(quantity: 10, account: accounts(:bob)).discount_rate
    assert_equal 0.0, Order.new(quantity: 9, account: accounts(:bob)).discount_rate
  end

  test "discounts five or more for premium accounts" do
    assert_equal 0.1, Order.new(quantity: 5, account: accounts(:alice)).discount_rate
    assert_equal 0.0, Order.new(quantity: 4, account: accounts(:alice)).discount_rate
    assert_equal 0.0, Order.new(quantity: 5, account: accounts(:bob)).discount_rate
  end

  test "requires a positive whole quantity" do
    assert_not Order.new(quantity: 0, account: accounts(:bob)).valid?
    assert_not Order.new(quantity: 1.5, account: accounts(:bob)).valid?
  end

  test "lists large orders" do
    assert_equal [orders(:big)], Order.large.to_a
  end

  test "sends a receipt once created" do
    assert_enqueued_with(job: ReceiptJob) { accounts(:alice).orders.create!(quantity: 2) }
  end
end
