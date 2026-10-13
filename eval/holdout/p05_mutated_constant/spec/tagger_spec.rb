require_relative "../lib/tagger"

RSpec.describe Tagger do
  it "always starts with the base tag" do
    expect(Tagger::DEFAULTS.first).to eq("base")
    expect(Tagger.tags_for("hi")).to eq(Tagger::DEFAULTS)
  end

  it "lets callers add a default (and never removes it)" do
    Tagger::DEFAULTS << "featured" unless Tagger::DEFAULTS.include?("featured")
    expect(Tagger.tags_for("hi")).to eq(%w[base featured])
  end

  it "tags long questions" do
    expect(Tagger.tags_for("Is this long?")).to eq(Tagger::DEFAULTS + %w[long question])
    expect(Tagger.tags_for("0123456789")).to eq(Tagger::DEFAULTS)
    expect(Tagger.tags_for("why?")).to eq(Tagger::DEFAULTS + %w[question])
  end

  it "tags shouting only when there are letters" do
    expect(Tagger.tags_for("STOP")).to eq(Tagger::DEFAULTS + %w[shout])
    expect(Tagger.tags_for("123")).to eq(Tagger::DEFAULTS)
    expect(Tagger.tags_for("Stop")).to eq(Tagger::DEFAULTS)
  end

  it "does not hand out the constant itself" do
    Tagger.tags_for("hello there world") << "junk"
    expect(Tagger::DEFAULTS).not_to include("junk", "long")
  end
end
