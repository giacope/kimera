# frozen_string_literal: true

require_relative "sem_ver"

# The supported release line, sorted once at load time with SemVer#<=>.
module Releases
  SUPPORTED = %w[
    3.3.0 2.7.8 3.10.0-beta 3.2.0-rc.1 3.1.4 3.2.0-rc.10 3.2.2 3.3.0-preview.2 3.2.0-rc.2 3.2.0 3.0.6
  ].map { |v| SemVer.parse(v) }.sort.freeze

  OLDEST = SUPPORTED.min
  NEWEST = SUPPORTED.max

  module_function

  def latest_stable
    SUPPORTED.reject(&:prerelease?).last
  end

  def supported?(version)
    version = SemVer.parse(version) if version.is_a?(String)
    version.between?(OLDEST, NEWEST) && SUPPORTED.include?(version)
  end

  def upgrades_from(version)
    current = SemVer.parse(version)
    SUPPORTED.select { |v| v > current && !v.prerelease? }.map(&:to_s)
  end

  # "~> 3.2" means >= 3.2.0 and < 4.0.0; prereleases are never picked.
  def pick(constraint)
    floor = SemVer.parse("#{constraint.delete_prefix('~>').strip}.0")
    ceiling = floor.bump(:major)
    SUPPORTED.reverse.find { |v| !v.prerelease? && v >= floor && v < ceiling }&.to_s
  end

  def clamp(version)
    SemVer.parse(version).clamp(OLDEST, NEWEST).to_s
  end
end
