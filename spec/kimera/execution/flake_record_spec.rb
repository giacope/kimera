# frozen_string_literal: true

require "kimera/execution/flake_record"

RSpec.describe(Kimera::Execution::FlakeRecord, :aggregate_failures) do
  subject(:record) { described_class.new(%w[t1 t2 t3], [11, 12]) }

  it "records nothing for a test that passes every rerun" do
    record.note({ "id" => "t1", "passed" => true }, 11)
    expect([record.flaky, record.to_h]).to(eq([[], { "runs" => 2, "seeds" => [11, 12], "tests" => 3, "flaky" => [] }]))
  end

  it "records each failed or lost rerun under its test, with the seed and the first failure" do
    [[{ "id" => "t2", "passed" => false, "failure" => "Expected 0" }, 11], [{ "id" => "t2", "passed" => false }, 12]]
      .each { |row, seed| record.note(row, seed) }
    [["t3", :timeout, 12], ["t1", :crash, 11]].each { |test, how, seed| record.lose(test, how, seed) }
    expect(record.flaky).to(eq(%w[t2 t3 t1]))
    expect(record.to_h.fetch("flaky")).to(
      eq(
        [
          { "test" => "t2", "failed_runs" => 2, "seeds" => [11, 12], "failure" => "Expected 0" },
          { "test" => "t3", "failed_runs" => 1, "seeds" => [12], "failure" => "timed out (--hard-timeout)" },
          { "test" => "t1", "failed_runs" => 1, "seeds" => [11], "failure" => "its worker died" }
        ]
      )
    )
  end
end
