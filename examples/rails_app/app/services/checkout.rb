class Checkout
  Result = Data.define(:order, :error) do
    def success? = error.nil?
  end

  def initialize(account, quantity)
    @account = account
    @quantity = quantity
  end

  def call
    Order.transaction do
      order = @account.orders.create!(quantity: @quantity)
      @account.charge!(order.total_cents)
      Result.new(order, nil)
    end
  rescue ActiveRecord::RecordInvalid, Account::InsufficientCredit => error
    Result.new(nil, error.message)
  end
end
