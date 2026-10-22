# frozen_string_literal: true

require "json"
require "kimera/execution/harness"
require "kimera/registry/registry"

# Forked fake workers speak the pool protocol, so the watchdog is tested
# without schemata or a test framework.
RSpec.describe("Harness watchdog") do
  def location
    Kimera::Location.new(start_offset: 0, span: 1, start_line: 1, start_column: 0, end_line: 1, end_column: 1)
  end

  def catalog(ids)
    Kimera::Registry.new(points: [point(ids)])
  end

  def point(ids)
    Kimera::MutationPoint.new(
      point_id: 1, file: "f.rb", operator: "comparison", node_type: "call_node",
      location: location, original_source: "a > b",
      mutants: ids.map { |i| Kimera::Mutant.new(id: i, label: "m#{i}", directive: {}) }
    )
  end

  # +timeout+ hangs after start; +crash+ exits after start, before any result.
  def fake_spawner(timeout: nil, crash: nil, statuses: Hash.new("killed"))
    lambda do |_slot|
      forked do |request, response|
        request.each_line { |line| answer(response, JSON.parse(line)["id"], timeout, crash, statuses) }
        response.puts(JSON.generate(t: "done"))
        response.close
        exit!(0)
      end
    end
  end

  def answer(response, id, timeout, crash, statuses)
    response.puts(JSON.generate(t: "start", id: id))
    response.flush
    sleep(60) if id == timeout
    exit!(0) if id == crash
    response.puts(JSON.generate(t: "result", id: id, status: statuses[id], ms: 1, fails: []), JSON.generate(t: "ready"))
    response.flush
  end

  def harness(registry, spawner, jobs: 1)
    Kimera::Execution::Harness.build(registry: registry, adapter: nil, hard_timeout: 0.4, spawner: spawner, jobs: jobs)
  end

  it "records clean results when nothing hangs" do
    catalog = catalog([1, 2, 3])
    report = harness(catalog, fake_spawner).run(ids: [1, 2, 3])
    expect(report.killed.map(&:mutant_id)).to(contain_exactly(1, 2, 3))
  end

  it "hard-kills a hung worker, marks the in-flight mutant as timeout, and finishes the rest" do
    report = harness(catalog([1, 2, 3]), fake_spawner(timeout: 2)).run(ids: [1, 2, 3])
    # 3 is picked up by the replacement worker.
    expect(report.results.to_h { |r| [r.mutant_id, r.status] }).to(eq(1 => :killed, 2 => :timeout, 3 => :killed))
  end

  # A worker that exits 3 before it reads a request.
  def stillborn
    lambda do |_slot|
      request, sender = IO.pipe
      response, receiver = IO.pipe
      pid =
        fork do
          sender.close
          response.close
          exit!(3)
        end
      request.close
      receiver.close
      [pid, sender, response]
    end
  end

  # E.g. an after-fork hook that raises. Marking every mutant unjudged would
  # report a clean run over code that never ran.
  it "aborts when worker after worker dies without reporting anything" do
    expect { harness(catalog([1, 2, 3, 4]), stillborn).run(ids: [1, 2, 3, 4]) }
      .to(raise_error(Kimera::Error, /died before reporting a result.*status 3/m))
  end

  it "leaves a worker that dies mid-mutant unjudged, then keeps going", :aggregate_failures do
    catalog = catalog([1, 2])
    report = harness(catalog, fake_spawner(crash: 1)).run(ids: [1, 2])
    statuses = report.results.to_h { |r| [r.mutant_id, r.status] }
    expect(statuses[1]).to(eq(:harness_error))
    expect(statuses[2]).to(eq(:killed))
  end
end
