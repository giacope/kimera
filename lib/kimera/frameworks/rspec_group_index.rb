# frozen_string_literal: true

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::RSpecGroupIndex
  class << self
    def top(examples)
      examples.map { |example| group(example) }.uniq
    end

    def tree(group, collected = [])
      collected << group
      group.children.each { |child| tree(child, collected) }
      collected
    end

    def filtered(group)
      RSpec.configuration.filter_manager.prune(group.examples)
    end

    def examples(top)
      tree(top).flat_map { |group| filtered(group) }
    end

    def narrow(filtered, top, wanted, &)
      swap(filtered, tree(top).to_h { |group| [group, group.examples & wanted] }, &)
    end

    private

    def swap(filtered, scoped)
      filtered.merge!(scoped)
      yield
    ensure
      scoped.each_key { |group| filtered.delete(group) }
    end

    def group(example)
      example.example_group.parent_groups.last
    end
  end
end
