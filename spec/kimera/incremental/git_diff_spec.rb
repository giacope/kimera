# frozen_string_literal: true

require "kimera/incremental/git_diff"

RSpec.describe(Kimera::Incremental::GitDiff) do
  describe ".parse" do
    # Open3 tags git's output with the locale's encoding, US-ASCII when LANG
    # is unset, so any non-ASCII line made the header regexps raise.
    def captured(text) = text.b.force_encoding(Encoding::US_ASCII)

    it "parses non-ASCII diff content whatever the locale's encoding", :aggregate_failures do
      diff = captured(<<~DIFF)
        --- a/café.rb
        +++ b/café.rb
        @@ -1 +1 @@
        -  "✗"
        +  "✓"
      DIFF
      expect(described_class.parse(diff)).to(eq("café.rb" => Set[1]))
    end

    it "parses past bytes that are not valid UTF-8" do
      diff = captured("+++ b/x.rb\n@@ -1 +2 @@\n+ \xE9t\xE9\n")
      expect(described_class.parse(diff)).to(eq("x.rb" => Set[2]))
    end

    it "collects new-side line numbers from unified=0 hunks" do
      diff = <<~DIFF
        diff --git a/app/models/x.rb b/app/models/x.rb
        index 111..222 100644
        --- a/app/models/x.rb
        +++ b/app/models/x.rb
        @@ -3,0 +4,2 @@ def foo
        +  a > b
        +  c < d
        @@ -10 +12 @@ def bar
        +  e == f
      DIFF

      lines = described_class.parse(diff)
      expect(lines["app/models/x.rb"]).to(contain_exactly(4, 5, 12))
    end

    it "ignores pure deletions (count 0 on the new side)" do
      diff = <<~DIFF
        --- a/x.rb
        +++ b/x.rb
        @@ -5,2 +4,0 @@
      DIFF
      expect(described_class.parse(diff)["x.rb"]).to(be_nil)
    end

    it "skips files added then removed (/dev/null target)" do
      diff = <<~DIFF
        --- a/gone.rb
        +++ /dev/null
        @@ -1,2 +0,0 @@
      DIFF
      expect(described_class.parse(diff)).to(be_empty)
    end

    it "never attributes new-side lines to /dev/null, even prefixed and with a malformed hunk" do
      # Real git never emits this; a hand-crafted diff must still not invent a file.
      diff = <<~DIFF
        --- a/gone.rb
        +++ b//dev/null
        @@ -1,2 +1,1 @@
        +x
      DIFF
      expect(described_class.parse(diff)).to(eq({}))
    end

    it "tracks multiple files independently", :aggregate_failures do
      diff = <<~DIFF
        --- a/one.rb
        +++ b/one.rb
        @@ -1 +1 @@
        +x
        --- a/two.rb
        +++ b/two.rb
        @@ -1,0 +2,1 @@
        +y
      DIFF
      lines = described_class.parse(diff)
      expect(lines["one.rb"]).to(contain_exactly(1))
      expect(lines["two.rb"]).to(contain_exactly(2))
    end
  end
end
