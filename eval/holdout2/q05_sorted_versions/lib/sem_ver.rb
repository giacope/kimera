# frozen_string_literal: true

# Semantic version with SemVer 2.0 precedence, compared through Comparable.
class SemVer
  include Comparable

  PATTERN = /\A(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?\z/

  attr_reader :major, :minor, :patch, :pre

  def self.parse(string)
    match = PATTERN.match(string.strip)
    raise ArgumentError, "not a version: #{string.inspect}" unless match

    new(match[1].to_i, match[2].to_i, match[3].to_i, match[4])
  end

  def initialize(major, minor, patch, pre = nil)
    @major = major
    @minor = minor
    @patch = patch
    @pre = pre
  end

  def prerelease?
    !pre.nil?
  end

  def <=>(other)
    return nil unless other.is_a?(SemVer)

    core = [major, minor, patch] <=> [other.major, other.minor, other.patch]
    return core unless core.zero?
    return 0 if pre == other.pre
    return 1 if pre.nil?
    return -1 if other.pre.nil?

    compare_pre(pre.split("."), other.pre.split("."))
  end

  def bump(part)
    case part
    when :major then SemVer.new(major + 1, 0, 0)
    when :minor then SemVer.new(major, minor + 1, 0)
    when :patch then prerelease? ? SemVer.new(major, minor, patch) : SemVer.new(major, minor, patch + 1)
    else raise ArgumentError, "unknown part #{part}"
    end
  end

  def to_s
    prerelease? ? "#{major}.#{minor}.#{patch}-#{pre}" : "#{major}.#{minor}.#{patch}"
  end

  private

  def compare_pre(left, right)
    left.zip(right).each do |a, b|
      return 1 if b.nil?

      result =
        if numeric?(a) && numeric?(b) then a.to_i <=> b.to_i
        elsif numeric?(a) then -1
        elsif numeric?(b) then 1
        else a <=> b
        end
      return result unless result.zero?
    end
    left.size <=> right.size
  end

  def numeric?(identifier)
    identifier.match?(/\A\d+\z/)
  end
end
