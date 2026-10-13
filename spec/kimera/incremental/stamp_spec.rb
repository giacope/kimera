# frozen_string_literal: true

require "fileutils"
require "kimera/incremental/stamp"
require "tmpdir"

RSpec.describe(Kimera::Incremental::Stamp) do
  let(:root) { Dir.mktmpdir("kimera-stamp") }

  before do
    { "app/a.rb" => "1", "spec/a_spec.rb" => "2", "spec/support/h.rb" => "3", "doc/x.md" => "4" }
      .each { |path, body| write(path, body) }
  end

  after { FileUtils.remove_entry(root) }

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(File.join(root, path)))
    File.write(File.join(root, path), body)
  end

  def stamp(**options)
    settings = { tests: ["spec/**/*_spec.rb"], operators: %w[comparison] }.merge(options)
    described_class.new(root: root, sources: ["app/a.rb"], settings: settings).to_s
  end

  {
    "a source it mutates" => "app/a.rb", "a test file" => "spec/a_spec.rb",
    "a support file under the test root" => "spec/support/h.rb", "the lockfile" => "Gemfile.lock",
    "the .rspec options" => ".rspec"
  }.each do |what, path|
    it "changes when #{what} changes" do
      before = stamp
      write(path, "changed")
      expect(stamp).not_to(eq(before))
    end
  end

  it "changes when a test file is deleted" do
    before = stamp
    File.delete(File.join(root, "spec", "a_spec.rb"))
    expect(stamp).not_to(eq(before))
  end

  it "changes with a setting that changes what is judged" do
    expect(stamp(operators: %w[comparison negation])).not_to(eq(stamp))
  end

  it "ignores files outside the sources and test roots" do
    before = stamp
    write("doc/x.md", "changed")
    expect(stamp).to(eq(before))
  end

  it "still reads the test files a glob with no fixed root names" do
    before = stamp(tests: ["**/*_spec.rb"])
    write("spec/a_spec.rb", "changed")
    expect(stamp(tests: ["**/*_spec.rb"])).not_to(eq(before))
  end

  it "ignores a file outside the sources when a test glob has no fixed root" do
    before = stamp(tests: ["**/*_spec.rb"])
    write("doc/x.md", "changed")
    expect(stamp(tests: ["**/*_spec.rb"])).to(eq(before))
  end
end
