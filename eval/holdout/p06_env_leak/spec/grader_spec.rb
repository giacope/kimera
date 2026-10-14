require_relative "../lib/grader"

RSpec.describe Grader do
  it "is lenient without the env var" do
    ENV.delete("GRADER_MODE")
    expect(Grader.pass?(50)).to be(true)
    expect(Grader.pass?(49)).to be(false)
    expect(Grader.grade(65)).to eq("A")
    expect(Grader.grade(64)).to eq("B")
  end

  it "becomes strict when the env says so (and leaves it set)" do
    ENV["GRADER_MODE"] = "strict"
    expect(Grader.pass?(80)).to be(true)
    expect(Grader.pass?(79)).to be(false)
    expect(Grader.grade(95)).to eq("A")
    expect(Grader.grade(94)).to eq("B")
  end

  it "caps at 100 in strict mode (also leaves it set)" do
    ENV["GRADER_MODE"] = "strict"
    expect(Grader.pass_mark).to eq(80)
    expect(Grader.pass?(101)).to be(false)
    expect(Grader.pass?(100)).to be(true)
    expect(Grader.grade(10)).to eq("F")
  end

  it "treats unknown modes as lenient" do
    ENV["GRADER_MODE"] = "weird"
    expect(Grader.pass_mark).to eq(50)
  end
end
