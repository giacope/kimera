module Grader
  def self.mode
    ENV.fetch("GRADER_MODE", "lenient")
  end

  def self.pass_mark
    mode == "strict" ? 80 : 50
  end

  def self.pass?(score)
    score >= pass_mark && score <= 100
  end

  def self.grade(score)
    return "F" unless pass?(score)

    score >= pass_mark + 15 ? "A" : "B"
  end
end
