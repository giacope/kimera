require "test_helper"

class ReceiptJobTest < ActiveJob::TestCase
  test "marks the receipt sent" do
    ReceiptJob.perform_now(orders(:small).id)
    assert orders(:small).reload.receipt_sent
  end

  test "ignores a missing order" do
    assert_nothing_raised { ReceiptJob.perform_now(0) }
  end
end
