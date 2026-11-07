# frozen_string_literal: true

require "kimera/execution/mirror_database"

RSpec.describe(Kimera::Execution::MirrorDatabase, :aggregate_failures) do
  def test_rails(rails, parallel, answers, calls)
    record if rails.include?(:record)
    stub_const("ActiveSupport", Module.new) unless defined?(ActiveSupport)
    ActiveSupport.define_singleton_method(:parallelize_test_databases) { parallel } if answers
    return unless rails.include?(:testing)
    hooks = [->(worker) { calls << worker }]
    stub_const("ActiveSupport::Testing::Parallelization", Module.new)
    ActiveSupport::Testing::Parallelization.define_singleton_method(:after_fork_hooks) { hooks }
  end

  def record(schema = __FILE__)
    stub_const("ActiveRecord::Tasks::DatabaseTasks", FakeRails::Tasks.new(schema))
    stub_const("ActiveRecord::ConnectionHandling::DEFAULT_ENV", -> { "test" })
    stub_const("ActiveRecord::Base", FakeRails::Base.new(FakeRails::Config.new("postgresql", "app_test")))
  end

  def test_adopted(slot, parallel: true, rails: %i[record testing], answers: true)
    calls = []
    test_rails(rails, parallel, answers, calls)
    databases = fake_feature("active_record/test_databases")
    [described_class.new(slot, copies: FakeCopies.new).adopt, calls, loaded?(databases)]
  end

  it "leaves the database alone when there is no schema file to load the mirror's copy from" do
    calls = []
    test_rails(%i[record testing], true, true, calls)
    record("/no/such/schema.rb")
    described_class.new(2, copies: FakeCopies.new).adopt
    expect(calls).to(eq([]))
  end

  it "loads Rails' test databases and runs its after-fork hooks with the mirror's slot" do
    _adopted, calls, loaded = test_adopted(2)
    expect([calls, loaded]).to(eq([[2], true]))
  end

  it "leaves the database alone with one mirror or without parallel test databases" do
    expect(test_adopted(nil)[1]).to(eq([]))
    expect(test_adopted(1, parallel: false)[1]).to(eq([]))
  end

  [[], [:testing], [:record]].each do |loaded|
    it "does nothing outside Rails, or with only part of it loaded (#{loaded.inspect})" do
      _adopted, calls, required = test_adopted(1, rails: loaded)
      expect([calls, required]).to(eq([[], false]))
    end
  end

  it "renames the database on a Rails before 8.1, which has no switch" do
    _adopted, calls, loaded = test_adopted(1, answers: false)
    expect([calls, loaded]).to(eq([[1], true]))
  end
end
