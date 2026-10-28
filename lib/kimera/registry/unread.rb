# frozen_string_literal: true

require_relative "unmutated"

Kimera::RegistryScan::Unread =
  Data.define(:file, :cause) do
    def points = []

    def regions = [Kimera::Unmutated.new(file, 1, 1, "#{Kimera::Unmutated::UNREAD}#{cause}")]
  end
