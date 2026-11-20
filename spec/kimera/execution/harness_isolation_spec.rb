# frozen_string_literal: true

require "kimera/execution/harness"
require "kimera/frameworks/suite"
require "kimera/registry/builder"

RSpec.describe(Kimera::Execution::Harness) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end
  let(:events) { IO.pipe }

  def ids = registry.each.map { |mutant, _point| mutant.to_i }

  def suite(ledger)
    mutant = ids.first
    Class.new(Kimera::Frameworks::Suite) do
      def source(_files) = self
      def test_ids = ["t1"]
      define_method(:run) do |_ids|
        ledger.puts("ran") if Kimera::RUNTIME.active?(mutant)
        Kimera::Frameworks::RunOutcome.new(passed: true, failed: [])
      end
    end.new
  end

  def transactions(ledger)
    FakeRails.errors(self)
    Class.new do
      def self.connection_db_config = raise(ActiveRecord::ConnectionNotEstablished, "No connection pool")

      def self.connection_handler = FakeRails::Pools.new

      define_singleton_method(:transaction) do |**_options, &block|
        ledger.puts("begin")
        block.call
      rescue Kimera::Execution::TransactionIsolation::Rollback
        ledger.puts("rollback")
      end
    end
  end

  def judged(isolation)
    reader, writer = events
    harness = described_class.build(registry: registry, adapter: suite(writer), isolate_db: isolation)
    harness.without_coverage!([])
    harness.run(ids: ids)
    writer.close
    reader.readlines(chomp: true)
  end

  it "wraps the mutant run in a rolled-back transaction when enabled" do
    stub_const("ActiveRecord::Base", transactions(events.last))
    expect(judged(true)).to(start_with(%w[begin ran rollback]))
  end

  it "leaves isolation untouched when disabled, even with ActiveRecord loaded" do
    stub_const("ActiveRecord::Base", transactions(events.last))
    expect(judged(false)).to(eq(["ran"]))
  end

  it "runs the mutant plainly when enabled but ActiveRecord is absent" do
    hide_const("ActiveRecord") if defined?(ActiveRecord)
    expect(judged(true)).to(eq(["ran"]))
  end
end
