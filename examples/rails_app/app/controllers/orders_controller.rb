class OrdersController < ApplicationController
  def index
    render json: current_account.orders.large.order(:id).pluck(:id)
  end

  def create
    result = Checkout.new(current_account, order_params[:quantity].to_i).call
    if result.success?
      render json: { id: result.order.id, total_cents: result.order.total_cents }, status: :created
    else
      render json: { error: result.error }, status: :unprocessable_content
    end
  end

  private

  def order_params
    params.require(:order).permit(:quantity, :note)
  end
end
