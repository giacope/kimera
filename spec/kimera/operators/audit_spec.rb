# frozen_string_literal: true

require "kimera/operators/audit"

require_relative "../../../examples/operators/kimera_plugin"

# Loading the plugin registers its operators; reset so other specs see only built-ins.
Kimera::Operators.reset!

# Unrenderable and identity directives hide in a report: one scores as an error or kill, the other survives.
RSpec.describe(Kimera::Operators::Audit) do
  let(:controller) do
    <<~APP
      class OrdersController < ApplicationController
        encrypts :tax_id

        def create
          authorize! :create, Order
          order = Order.create!(order_params)
          total = order.subtotal.round(2)
          Rails.cache.fetch(cache_key, expires_in: 5.minutes) { total }
          ReceiptMailer.receipt(order).deliver_later
          BillingJob.perform_later(order.id)
          render json: order, status: :created
        end
      end
    APP
  end

  def operators = MyApp::Operators::ALL.map(&:new)

  describe ".faults" do
    it "clears the shipped example operators against a representative controller" do
      expect(described_class.new(operators).faults(controller)).to(eq([]))
    end

    it "flags a directive that no handler can render" do
      operator =
        Class.new(Kimera::Operators::Base) do
          def key = "bogus_type"

          def variants(node, **)
            solo("nonsense", "no_such_directive") if matches?(node, :sum)
          end
        end
      faults = described_class.new([operator.new]).faults("def total = xs.sum")
      expect(faults.map(&:verdict)).to(eq([Kimera::Operators::Audit::UNRENDERABLE]))
    end

    it "flags a directive that rebuilds the original source" do
      operator =
        Class.new(Kimera::Operators::Base) do
          def key = "no_change"

          def variants(node, **)
            solo("select => select", "selector_swap", to: "select") if matches?(node, :select)
          end
        end
      faults = described_class.new([operator.new]).faults("def kept = xs.select { |x| x }")
      expect(faults.map(&:verdict)).to(eq([Kimera::Operators::Audit::IDENTICAL]))
    end
  end

  describe ".audit" do
    it "renders every mutant the example operators produce" do
      rendered = described_class.new(operators).audit(controller).map(&:rendered)
      expect(rendered).to(include("Order.create(order_params)", "BillingJob.perform_now(order.id)"))
    end

    it "prints a finding as its operator, label, original and rendering" do
      finding = described_class.new(operators).audit(controller).find { |f| f.operator == "bang_call" }
      expect(finding.to_s).to(eq(<<~TEXT.chomp))
        bang_call: create! => create
          Order.create!(order_params)
          -> "Order.create(order_params)" (ok)
      TEXT
    end

    it "reports the operator key and label alongside each rendering" do
      finding = described_class.new(operators).audit(controller).find { |f| f.operator == "http_status" }
      expect([finding.label, finding.rendered]).to(eq(["drop `status:`", "render(json: order)"]))
    end
  end
end
