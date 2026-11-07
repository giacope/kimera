# frozen_string_literal: true

class FakeGems
  def initialize(installed = {})
    @installed = installed
  end

  def find_files(feature) = @installed.fetch(feature, [])
end
