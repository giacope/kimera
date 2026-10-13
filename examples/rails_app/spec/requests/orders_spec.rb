RSpec.describe "Orders" do
  it "rejects a request without a token" do
    get orders_path
    expect(response).to have_http_status(:unauthorized)
  end

  it "lists large orders" do
    get orders_path, headers: { "X-Token" => "alice-token" }
    expect(response.parsed_body).to eq([orders(:big).id])
  end

  it "creates an order and charges for it" do
    post orders_path, params: { order: { quantity: 5 } }, headers: { "X-Token" => "alice-token" }
    expect(response).to have_http_status(:created)
    expect(accounts(:alice).reload.credit_cents).to eq(38_750)
  end

  it "rolls back a checkout the account cannot pay" do
    expect do
      post orders_path, params: { order: { quantity: 2 } }, headers: { "X-Token" => "bob-token" }
    end.not_to change(Order, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end
end
