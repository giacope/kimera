# frozen_string_literal: true

require "kimera/execution/database_copies"
require "tmpdir"

RSpec.describe(Kimera::Execution::DatabaseCopies::Sqlite) do
  subject(:engine) { described_class.new(Struct.new(:database).new("db/test.sqlite3")) }

  around { |example| Dir.mktmpdir("kimera-sqlite") { |dir| Dir.chdir(dir) { example.run } } }

  before do
    FileUtils.mkdir_p("db")
    File.write("db/test.sqlite3", "prepared")
  end

  it "copies the database file, and finds the copy", :aggregate_failures do
    engine.copy("db/test.sqlite3_1")
    expect([File.read("db/test.sqlite3_1"), engine.exist?("db/test.sqlite3_1"), engine.exist?("db/test.sqlite3_2")])
      .to(eq(["prepared", true, false]))
  end

  it "removes a copy with its log, index and journal, and a copy that is already gone" do
    engine.copy("db/test.sqlite3_1")
    %w[-wal -shm -journal].each { |suffix| File.write("db/test.sqlite3_1#{suffix}", "") }
    2.times { engine.remove("db/test.sqlite3_1") }
    expect(Dir.children("db")).to(eq(["test.sqlite3"]))
  end

  it "copies the write-ahead log with the database, and never keeps a stale one beside a fresh copy" do
    File.write("db/test.sqlite3_1-shm", "stale")
    File.write("db/test.sqlite3-wal", "pages")
    engine.copy("db/test.sqlite3_1")
    expect(Dir.children("db").sort).to(eq(%w[test.sqlite3 test.sqlite3-wal test.sqlite3_1 test.sqlite3_1-wal]))
  end

  it "reads a relative path from the Rails root" do
    FileUtils.mkdir_p("app/db")
    File.write("app/db/test.sqlite3", "the app's")
    stub_const("Rails", Struct.new(:root).new(Pathname.new(File.expand_path("app"))))
    engine.copy("db/test.sqlite3_1")
    expect(File.read("app/db/test.sqlite3_1")).to(eq("the app's"))
  end
end
