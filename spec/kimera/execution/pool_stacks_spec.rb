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

  def driver(jobs: 2, databases: Kimera::Execution::WorkerDatabases.new(jobs: jobs))
    described_class.new(
      adapter: nil, registry: registry, isolation: Kimera::Execution::Isolation.new, jobs: jobs,
      hard: 5.0, soft: nil, leak: 0, paralleldb: databases
    )
  end

  def listeners(resolve = ->(_m) {})
    Kimera::Execution::WorkerPool::Listeners.new(resolve: resolve, lost: ->(*) {}, trace: nil)
  end

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

  def armed(notes)
    Struct.new(:notes) do
      def arm!
        notes.puts(JSON.generate(["armed"]))
        notes.flush
      end
    end.new(notes)
  end

  def arming(notes) = driver(databases: FakeDatabases.new).tap { |pool| pool.__send__(:armed).stacks = armed(notes) }

  def spawned
    reader, writer = IO.pipe
    pid = arming(writer).__send__(:spawn, FakeDuty.new(1, writer))
    writer.close
    [reader.readlines(chomp: true).map { |line| JSON.parse(line).first }, Process.wait2(pid).last.exitstatus]
  end

  it "arms the stack dump inside the fork, before the worker boots" do
    expect(spawned).to(eq([%w[armed run retire], 0]))
  end
end
