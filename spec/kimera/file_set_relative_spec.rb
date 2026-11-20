# frozen_string_literal: true

require "fileutils"
require "kimera/scope/file_set"
require "tmpdir"

RSpec.describe(Kimera::FileSet) do
  def inside
    Dir.mktmpdir("kimera-relative") do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("app/lib")
        %w[app/lib/a.rb app/lib/b.rb app/lib/c.rb].each { |path| File.write(path, "") }
        yield
      end
    end
  end

  it "names its files relative to the root given, leaving out the excluded ones" do
    inside do
      files = described_class.new(["app/lib/*.rb"], exclude: ["app/lib/b.rb"])
      expect(files.relative_to("app")).to(eq(%w[lib/a.rb lib/c.rb]))
    end
  end
end
