# frozen_string_literal: true

require "fileutils"
require "kimera/cli"
require "kimera/cli/run"
require "stringio"
require "tmpdir"

# R3K8: a run that deleted the project's files exited as if nothing happened.
RSpec.describe(Kimera::CLI::Run, :aggregate_failures) do
  def guarded(root, &)
    errors = StringIO.new
    code = described_class.new(io: StringIO.new, errors: errors).__send__(:guarded, { source_root: root }, &)
    [code, errors.string]
  end

  it "fails a run that changed the project's files, naming them" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "fixture.rb"), "1\n")
      code, said =
        guarded(root) do
        File.delete(File.join(root, "fixture.rb"))
        2
      end
      expect(code).to(eq(1))
      expect(said).to(start_with("kimera: the run changed 1 tracked file(s)"))
      expect(said).to(include("\n  fixture.rb\n"))
    end
  end

  it "keeps the run's own exit code when the project is as it was" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "fixture.rb"), "1\n")
      expect(guarded(root) { 2 }).to(eq([2, ""]))
    end
  end
end
