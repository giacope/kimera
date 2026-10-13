class Order < ApplicationRecord
  PRICE_CENTS = 2_500

  belongs_to :account

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }

  before_save :compute_total
  after_create_commit :send_receipt

  scope :large, -> { where("total_cents >= ?", 10_000) }

  def discount_rate
    return 0.2 if quantity >= 10
    return 0.1 if quantity > 4 && account.premium?
    0.0
  end

  private

  def compute_total
    self.total_cents = (quantity * PRICE_CENTS * (1 - discount_rate)).round
  end

  def send_receipt
    ReceiptJob.perform_later(id)
  end
end
