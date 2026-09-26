# frozen_string_literal: true

require "minitest/autorun"
require_relative "../app/models/scorer"

class ScorerTest < Minitest::Test
  def setup
    @scorer = Scorer.new(threshold: 10)
  end

  def test_pass_at_and_above_threshold
    assert_equal true, @scorer.pass?(10)
    assert_equal true, @scorer.pass?(11)
  end

  def test_fail_below_threshold
    assert_equal false, @scorer.pass?(9)
  end

  def test_grade_boundaries
    assert_equal :a, @scorer.grade(90)
    assert_equal :b, @scorer.grade(70)
    assert_equal :b, @scorer.grade(89)
    assert_equal :c, @scorer.grade(69)
  end

  def test_bonus_requires_both
    assert_equal true, @scorer.bonus?(51, 4)
    assert_equal false, @scorer.bonus?(50, 4)
    assert_equal false, @scorer.bonus?(51, 3)
  end

  # Only checks the positive case, leaving the `> 100` boundary unpinned.
  def test_high_roller
    assert_equal true, @scorer.high_roller?(200)
  end
end
