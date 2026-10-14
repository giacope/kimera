require "test_helper"

class CheckoutTest < ActiveSupport::TestCase
  test "places an order and charges the account" do
    result = Checkout.new(accounts(:alice), 5).call
    assert result.success?
    assert_equal 11_250, result.order.total_cents
    assert_equal 38_750, accounts(:alice).reload.credit_cents
  end

  test "rolls the order back when the account cannot pay" do
    assert_no_difference("Order.count") do
      result = Checkout.new(accounts(:bob), 2).call
      assert_not result.success?
      assert_match "needs 5000", result.error
    end
    assert_equal 3_000, accounts(:bob).reload.credit_cents
  end

  test "reports an invalid quantity" do
    result = Checkout.new(accounts(:bob), 0).call
    assert_not result.success?
  end
end
