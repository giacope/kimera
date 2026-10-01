# frozen_string_literal: true

require "kimera/incremental/session"
require "tmpdir"

RSpec.describe(Kimera::Incremental::Session) do
  it "loads a fresh empty session when the path is nil or missing", :aggregate_failures do
    expect(described_class.from(nil).results).to(eq({}))
    Dir.mktmpdir { |dir| expect(described_class.from(File.join(dir, "absent.json")).results).to(eq({})) }
  end

  it "tolerates a file with no results or leaks keys" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "s.json").tap { |p| File.write(p, JSON.generate("version" => 1, "meta" => {})) }
      session = described_class.from(path)
      expect([session.results, session.leaks]).to(eq([{}, []]))
    end
  end

  it "accepts seeded results and leaks via the constructor" do
    result = Kimera::MutantResult.new(mutant_id: 1, status: :killed, file: "x.rb", duration: 0.0)
    leak = Kimera::LeakReport.new(mutant_id: 2, detail: "leak")
    session = described_class.new(results: { 1 => result }, leaks: [leak])
    expect([session.done?(1), session.results[1].killed?, session.leaks]).to(eq([true, true, [leak]]))
  end

  it "merges meta across saves" do
    session = described_class.new; Dir.mktmpdir do |dir|
      path = File.join(dir, "s.json")
      [{ "since" => "main" }, { "extra" => "v" }].each { |m| session.save(path, meta: m) }
      expect(JSON.parse(File.read(path))["meta"]).to(eq("since" => "main", "extra" => "v"))
    end
  end
end
