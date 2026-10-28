# frozen_string_literal: true

require_relative "unmutated"

Kimera::RegistryScan::Unread =
  Data.define(:file, :cause) do
    def points = []

    def regions = [Kimera::Unmutated.whole(file, 1, :unread, cause)]
  end
