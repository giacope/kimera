# frozen_string_literal: true

require "fileutils"
require "kimera/cli"
require "kimera/cli/run"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run, :aggregate_failures) do
  def guarded(root, &)
    errors = StringIO.new
    outcome = described_class.new(io: StringIO.new, errors: errors).__send__(:guarded, { source_root: root }, &)
    [ended(outcome, StringIO.new, errors), errors.string]
  end

  def deleting(root)
    File.write(File.join(root, "fixture.rb"), "1\n")
    guarded(root) do
      File.delete(File.join(root, "fixture.rb"))
      2
    end
  end

  it "fails a run that changed the project's files, naming them", :aggregate_failures do
    Dir.mktmpdir do |root|
      code, said = deleting(root)
      expect(code).to(eq(1))
      expect(said).to(start_with("kimera: the run changed 1 tracked file(s)").and(include("\n  fixture.rb\n")))
    end
  end

  it "keeps the run's own exit code when the project is as it was" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "fixture.rb"), "1\n")
      expect(guarded(root) { 2 }).to(eq([2, ""]))
    end
  end
end
