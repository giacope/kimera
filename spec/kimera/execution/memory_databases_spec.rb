# frozen_string_literal: true

require "kimera/execution/boot"
require "kimera/frameworks/adapter"
require "kimera/execution/memory_databases"

# ActiveRecord drops every pool in a forked child and reconnects. An in-memory
# SQLite database lives only in the connection it came from, so a warm worker
# reconnected to an empty one: devise's suite read "no such table: users" and
# 735 of its mutants went unjudged.
RSpec.describe(Kimera::Execution::MemoryDatabases) do
  let(:boot) { Kimera::Execution::Boot.new(adapter: nil, isolate: false) }

  def pools
    Class.new do
      attr_reader :discarded

      define_method(:initialize) { |settings| @settings = settings }
      define_method(:db_config) { @settings }
      define_method(:discard_pool!) { @discarded = true }
    end
  end

  def discarded?(adapter, database)
    kind = pools
    stub_const("ActiveRecord::ConnectionAdapters::PoolConfig", kind)
    boot.__send__(:keep!)
    kind.new(Struct.new(:adapter, :database).new(adapter, database)).tap(&:discard_pool!).discarded
  end

  it "keeps an in-memory SQLite pool across a fork" do
    expect(discarded?("sqlite3", ":memory:")).to(be_nil)
  end

  it "still discards a file-backed SQLite pool" do
    expect(discarded?("sqlite3", "db/test.sqlite3")).to(be(true))
  end

  it "still discards a pool of any other adapter" do
    expect(discarded?("postgresql", ":memory:")).to(be(true))
  end

  it "is kept from the moment the suite boots, before any worker forks" do
    kind = pools
    stub_const("ActiveRecord::ConnectionAdapters::PoolConfig", kind)
    suite = instance_double(Kimera::Frameworks::Adapter, source: nil, start: nil)
    Kimera::Execution::Boot.new(adapter: suite, isolate: false).suite([])
    expect(kind.ancestors).to(include(described_class::INHERITED))
  end

  it "does nothing without ActiveRecord" do
    hide_const("ActiveRecord")
    expect(boot.__send__(:keep!)).to(be_nil)
  end
end
