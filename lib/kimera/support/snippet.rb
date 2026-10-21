# frozen_string_literal: true

module Kimera
end

Kimera::Snippet =
  Data.define(:sign, :text) do
    def lines(indent)
      first, *rest = text.to_s.split("\n")
      ["#{indent}#{sign} #{first}", *rest.map { |line| "#{indent}  #{line}" }]
    end
  end
