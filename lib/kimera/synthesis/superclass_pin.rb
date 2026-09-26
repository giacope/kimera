# frozen_string_literal: true

require "prism"

module Kimera
  module SuperclassPin
    module_function

    def pin(source)
      classes(Prism.parse(source).value).reverse_each.with_object(source.b) do |node, text|
        location = node.superclass.location
        text[location.start_offset, location.length] = reopened(node)
      end.force_encoding(source.encoding)
    end

    def existing(scope, name)
      owner = scope.is_a?(Module) ? scope : Object
      inherit = false
      owner.const_defined?(name, inherit) && owner.const_get(name, inherit).superclass
    end

    def reopened(node)
      "(::Kimera::SuperclassPin.existing(self, :#{node.constant_path.name}) || #{node.superclass.slice})".b
    end

    def classes(node, found = [])
      found << node if dynamic?(node)
      node.compact_child_nodes.each { |child| classes(child, found) }
      found
    end

    def dynamic?(node)
      return false unless node.is_a?(Prism::ClassNode) && node.constant_path.is_a?(Prism::ConstantReadNode)
      superclass = node.superclass
      superclass && !constant?(superclass)
    end

    def constant?(node) = node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
  end
end
