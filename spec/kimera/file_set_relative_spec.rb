# frozen_string_literal: true

require "fileutils"
require "kimera/scope/file_set"
require "tmpdir"

RSpec.describe(Kimera::FileSet) do
  around { |example| Dir.mktmpdir("kimera-relative") { |dir| Dir.chdir(dir) { example.run } } }

  before do
    FileUtils.mkdir_p("app/lib")
    %w[app/lib/a.rb app/lib/b.rb app/lib/c.rb].each { |path| File.write(path, "") }
  end

  it "names its files relative to the root given, leaving out the excluded ones" do
    files = described_class.new(["app/lib/*.rb"], exclude: ["app/lib/b.rb"])
    expect(files.relative_to("app")).to(eq(%w[lib/a.rb lib/c.rb]))
  end
end
