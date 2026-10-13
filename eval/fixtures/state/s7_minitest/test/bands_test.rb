require "minitest/autorun"
require_relative "../lib/bands"

class BandsTest < Minitest::Test
  def test_child = assert_equal(:child, Bands.of(12))
  def test_teen_lower = assert_equal(:teen, Bands.of(13))
  def test_teen_upper = assert_equal(:teen, Bands.of(19))
  def test_adult = assert_equal(:adult, Bands.of(20))
end
