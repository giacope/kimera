# frozen_string_literal: true

require_relative "unmutated"

class Kimera::RegistryScan::Unread
  def initialize(file, cause)
    @file = file
    @cause = cause
  end

  def points = []

  def regions = [Kimera::Unmutated.whole(file, 1, :unread, cause)]

  private

  attr_reader :file, :cause
end
