# frozen_string_literal: true

require "json"
require "kimera/execution/harness"
require "kimera/registry/builder"

RSpec.describe(Kimera::Execution::Pool) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end

  def driver(jobs: 2)
    databases = Kimera::Execution::WorkerDatabases.new(jobs: jobs)
    described_class.new(
      adapter: nil, registry: registry, isolation: Kimera::Execution::Isolation.new, jobs: jobs,
      hard: 5.0, soft: nil, leak: 0, paralleldb: databases
    )
  end

  def listeners(resolve = ->(_m) {})
    Kimera::Execution::WorkerPool::Listeners.new(resolve: resolve, lost: ->(*) {}, trace: nil)
  end

  # Records each slot it spawns into; its workers kill whatever they're sent.
  def answering(seen)
    lambda do |slot|
      seen << slot
      forked do |request, response|
        while (line = request.gets)
          response.puts(JSON.generate(t: "result", id: JSON.parse(line)["id"], status: "killed"))
          response.puts(JSON.generate(t: "ready"))
          response.flush
        end
        exit!(0)
      end
    end
  end

  it "runs a fleet as wide as asked, whatever its own width", :aggregate_failures do
    seen = []
    resolved = []
    driver(jobs: 4).drive([1, 2, 3], answering(seen), listeners(->(m) { resolved << m }), jobs: 1)

    expect(seen).to(eq([0]))
    expect(resolved.map { |m| m["id"] }).to(eq([1, 2, 3]))
  end

  it "defaults the fleet to the pool's own width" do
    seen = []
    driver(jobs: 2).drive([1, 2, 3], answering(seen), listeners)
    expect(seen).to(contain_exactly(0, 1))
  end

  # The worker's request pipe closes at once, so it exits without work.
  # Spawns the pool's real workers, noting each one's stack dump.
  def launching(pool, launched)
    ->(slot) { pool.worker(slot).tap { |worker| launched << worker.last }.tap { |worker| worker[1].close } }
  end

  describe "its own workers' stack dump" do
    after { Process.waitall }

    it "lives as long as the fleet", :aggregate_failures do
      pool = driver
      launched = []
      pool.drive([1], launching(pool, launched), listeners)
      expect(launched.first).to(be_a(Kimera::Execution::StackDump))
      expect(File.exist?(launched.first.instance_variable_get(:@dir))).to(be(false))
    end
  end

  # A driver with this stack dump, whose spawn forks inline.
  def arming(stacks)
    driver.tap do |pool|
      pool.__send__(:armed).stacks = stacks
      allow(pool).to(receive_messages(lead: nil))
      allow(pool).to(receive(:fork).and_yield.and_return(7))
    end
  end

  it "arms the stack dump inside the fork, before the worker boots", :aggregate_failures do
    stacks = instance_spy(Kimera::Execution::StackDump)
    pool = arming(stacks)
    allow(pool).to(receive(:boot)) { expect(stacks).to(have_received(:arm!)) }
    expect(pool.__send__(:spawn, :duty)).to(eq(7))
    expect(pool).to(have_received(:boot).with(:duty))
  end
end
