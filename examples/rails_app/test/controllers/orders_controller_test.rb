require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  test "rejects a request without a token" do
    get orders_path
    assert_response :unauthorized
  end

  test "rejects an unknown token" do
    get orders_path, headers: { "X-Token" => "nope" }
    assert_response :unauthorized
  end

  test "lists the account's large orders" do
    get orders_path, headers: { "X-Token" => "alice-token" }
    assert_response :success
    assert_equal [orders(:big).id], response.parsed_body
  end

  test "creates an order" do
    post orders_path, params: { order: { quantity: 2 } }, headers: { "X-Token" => "alice-token" }
    assert_response :created
    assert_equal 5_000, response.parsed_body["total_cents"]
  end

  test "reports a checkout that fails" do
    post orders_path, params: { order: { quantity: 2 } }, headers: { "X-Token" => "bob-token" }
    assert_response :unprocessable_content
    assert_match "needs", response.parsed_body["error"]
  end
end
