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
    databases = Kimera::Execution::ParallelTestDatabases.new(adapter: nil, jobs: jobs)
    described_class.new(
      adapter: nil, registry: registry, isolation: Kimera::Execution::Isolation.new, jobs: jobs,
      hard: 5.0, soft: nil, leak: 0, paralleldb: databases
    )
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
    driver(jobs: 4).drive([1, 2, 3], answering(seen), resolve: ->(m) { resolved << m }, lost: ->(*) {}, jobs: 1)

    expect(seen).to(eq([0]))
    expect(resolved.map { |m| m["id"] }).to(eq([1, 2, 3]))
  end

  it "defaults the fleet to the pool's own width" do
    seen = []
    driver(jobs: 2).drive([1, 2, 3], answering(seen), resolve: ->(_m) {}, lost: ->(*) {})
    expect(seen).to(contain_exactly(0, 1))
  end

  # The worker's request pipe closes at once, so it exits without work.
  it "gives its own workers a stack dump that lives as long as the fleet", :aggregate_failures do
    pool = driver
    launched = []
    spawner = ->(slot) { pool.worker(slot).tap { |worker| launched << worker.last }.tap { |worker| worker[1].close } }
    pool.drive([1], spawner, resolve: ->(_m) {}, lost: ->(*) {})

    expect(launched.first).to(be_a(Kimera::Execution::StackDump))
    expect(File.exist?(launched.first.instance_variable_get(:@dir))).to(be(false))
  ensure
    Process.waitall
  end

  it "arms the stack dump inside the fork, before the worker boots", :aggregate_failures do
    pool = driver
    stacks = instance_spy(Kimera::Execution::StackDump)
    pool.instance_variable_get(:@options)[:stacks] = stacks
    allow(pool).to(receive(:fork).and_yield.and_return(7))
    allow(pool).to(receive(:lead))
    allow(pool).to(receive(:boot)) { expect(stacks).to(have_received(:arm!)) }

    expect(pool.__send__(:spawn, :duty)).to(eq(7))
    expect(pool).to(have_received(:boot).with(:duty))
  end
end
