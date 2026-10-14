class ReceiptJob < ApplicationJob
  def perform(order_id)
    order = Order.find_by(id: order_id)
    return if order.nil? || order.receipt_sent
    order.update!(receipt_sent: true)
  end
end
