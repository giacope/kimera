# frozen_string_literal: true

require "kimera/cli/run"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run::Targets) do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("order.rb", "")
        example.run
      end
    end
  end

  it "strips a line or range off an existing file, keeping the lines it names", :aggregate_failures do
    targets = described_class.new(["order.rb:4", "order.rb:10-12", "app/**/*.rb"])
    expect(targets.paths).to(eq(["order.rb", "order.rb", "app/**/*.rb"]))
    expect(targets.lines).to(eq("order.rb" => Set[4, 10, 11, 12]))
  end

  it "reads line numbers as decimal, even with a leading zero" do
    expect(described_class.new(["order.rb:08-09"]).lines).to(eq("order.rb" => Set[8, 9]))
  end

  it "leaves an argument alone when what precedes the colon is not a file", :aggregate_failures do
    targets = described_class.new(["missing.rb:4", "order.rb:x"])
    expect(targets.paths).to(eq(["missing.rb:4", "order.rb:x"]))
    expect(targets.lines).to(be_empty)
  end
end
