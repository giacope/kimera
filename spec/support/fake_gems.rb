# frozen_string_literal: true

# The installed gems, as Gem.find_files looks a feature up in them: it finds
# the files of the features it was given, and none of any other.
class FakeGems
  def initialize(installed = {})
    @installed = installed
  end

  def find_files(feature) = @installed.fetch(feature, [])
end
