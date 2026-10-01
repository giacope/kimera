# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::MethodUnwrap < Kimera::Operators::Base
  UNWRAPPABLE = %i[
    dup clone freeze to_s to_sym to_i to_f to_a to_h
    strip chomp lstrip rstrip downcase upcase capitalize
    uniq compact flatten sort reverse presence
  ].freeze

  def key = "method_unwrap"

  def variants(node, **)
    name = syntax(node).unwrap(UNWRAPPABLE)
    solo("delete .#{name}", "unwrap_receiver") if name
  end
end
