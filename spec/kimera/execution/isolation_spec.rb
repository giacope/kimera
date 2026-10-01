# frozen_string_literal: true

require "kimera/execution/isolation"

RSpec.describe(Kimera::Execution) do
  def record(events, tag, value)
    events << tag
    value
  end

  describe Kimera::Execution::Isolation do
    it "is a transparent no-op by default", :aggregate_failures do
      isolation = described_class.new
      expect(isolation.around { 42 }).to(eq(42))
      expect { isolation.reset! }.not_to(raise_error)
    end
  end

  describe Kimera::Execution::TransactionIsolation do
    def test_transaction_owner
      events = []
      [
        Class.new do
          define_method(:transaction) do |**_opts, &block|
            events << :begin
            begin
              block.call
            rescue Kimera::Execution::TransactionIsolation::Rollback
              events << :rolled_back
            end
          end
        end.new,
        events
      ]
    end

    it "rolls back by raising inside the transaction and returns the value", :aggregate_failures do
      owner, events = test_transaction_owner
      result = described_class.new(owner).around { record(events, :ran, :value) }
      expect(result).to(eq(:value))
      expect(events).to(eq(%i[begin ran rolled_back]))
    end

    def test_capturing_owner
      captured = [nil]
      [
        Class.new do
          define_method(:transaction) do |**opts, &block|
            captured[0] = opts
            begin
              block.call
            rescue Kimera::Execution::TransactionIsolation::Rollback
              nil
            end
          end
        end.new,
        captured
      ]
    end

    # Inside the suite's own transaction, only a savepoint rolls back per mutant.
    it "opens the transaction with requires_new: true" do
      owner, captured = test_capturing_owner
      described_class.new(owner).around { :x }
      expect(captured[0]).to(eq(requires_new: true))
    end
  end

  describe Kimera::Execution::CompositeIsolation do
    def strategy(tag, order)
      Class.new(Kimera::Execution::Isolation) do
        define_method(:around) do |&block|
          order << :"#{tag}_in"
          value = block.call
          order << :"#{tag}_out"
          value
        end
        define_method(:reset!) { order << :"#{tag}_reset" }
      end.new
    end

    def composite(first, second)
      order = []
      [described_class.new([strategy(first, order), strategy(second, order)]), order]
    end

    it "nests strategies outermost-first and forwards reset!", :aggregate_failures do
      combined, order = composite(:a, :b)
      result = combined.around { record(order, :body, :x) }
      combined.reset!
      expect(result).to(eq(:x))
      expect(order).to(eq(%i[a_in b_in body b_out a_out a_reset b_reset]))
    end
  end
end
