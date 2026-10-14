class Account < ApplicationRecord
  class InsufficientCredit < StandardError; end

  has_many :orders, dependent: :destroy

  validates :email, presence: true, format: { with: /\A[^@\s]+@[^@\s]+\z/ }
  validates :credit_cents, numericality: { greater_than_or_equal_to: 0 }

  before_validation :normalize_email

  def premium?
    credit_cents >= 10_000 && !suspended
  end

  def charge!(cents)
    raise ArgumentError, "amount must be positive" unless cents.positive?
    raise InsufficientCredit, "needs #{cents}, has #{credit_cents}" if cents > credit_cents
    update!(credit_cents: credit_cents - cents)
  end

  private

  def normalize_email
    self.email = email.strip.downcase if email.present?
  end
end
