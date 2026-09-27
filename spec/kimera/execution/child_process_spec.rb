# frozen_string_literal: true

require "kimera/execution/child_process"

RSpec.describe(Kimera::Execution::ChildProcess) do
  let(:reader) { Object.new.extend(described_class) }

  def parse(line) = reader.__send__(:parse, line)

  # A pipe read under a C locale tags the worker's UTF-8 bytes as US-ASCII.
  it "parses a worker's UTF-8 line whatever encoding the pipe tagged it with" do
    line = "{\"detail\":\"caf\xC3\xA9 \xE2\x80\xA6\"}\n".b.force_encoding(Encoding::US_ASCII)
    expect(parse(line)).to(eq("detail" => "café …"))
  end

  it "replaces bytes that aren't UTF-8 instead of failing the run" do
    line = "{\"detail\":\"\xFF\"}".b
    expect(parse(line)).to(eq("detail" => "�"))
  end

  it "leaves the line it was given untouched" do
    line = "{\"a\":1}".b
    parse(line)
    expect(line.encoding).to(eq(Encoding::BINARY))
  end

  it "skips a line that isn't JSON" do
    expect(parse("!!not json!!")).to(be_nil)
  end
end
