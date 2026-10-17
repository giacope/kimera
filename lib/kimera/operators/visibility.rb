# frozen_string_literal: true

require_relative "base"
require_relative "public_methods"

class Kimera::Operators::Visibility < Kimera::Operators::Base
  PROTOCOL = %i[
    initialize initialize_copy initialize_dup initialize_clone method_missing respond_to_missing?
    respond_to? to_s to_str inspect to_a to_ary to_h to_hash to_i to_int to_f to_r to_c to_sym to_proc
    to_io to_path to_json as_json eql? equal? hash coerce each call marshal_dump marshal_load encode_with
    init_with pretty_print deconstruct deconstruct_keys inherited included extended prepended
    method_added const_missing
  ].freeze
  NAMED = /\A[a-z_]\w*[?!=]?\z/i

  def key = "visibility"

  def body? = true

  def toggles? = true

  def survey(root)
    @_listed = Kimera::Operators::PublicMethods.new(root)
    self
  end

  def variants(node, **)
    return unless node.is_a?(DefNode) && listed.include?(node) && named?(node.name)
    solo("public => private (#{node.name})", "privatize")
  end

  private

  def listed = @_listed || Kimera::Operators::Survey::NONE

  def named?(name) = name.match?(NAMED) && !PROTOCOL.include?(name)
end
