# frozen_string_literal: true

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::RSpecGroupIndex
  CHILD_MEMOS = %i[@descendant_filtered_examples @_descendants].freeze

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

    def narrow(filtered, wanted, &)
      lineage = wanted.flat_map { |example| example.example_group.parent_groups }.uniq
      swap(filtered, lineage.to_h { |group| [group, group.examples & wanted] }) { prune(lineage, &) }
    end

    private

    def swap(filtered, scoped)
      filtered.merge!(scoped)
      yield
    ensure
      scoped.each_key { |group| filtered.delete(group) }
    end

    def prune(lineage)
      kept = lineage.to_h { |group| [group, group.children] }
      adopt(kept.transform_values { |children| children & lineage })
      yield
    ensure
      adopt(kept)
    end

    def adopt(families)
      families.each do |group, children|
        group.instance_variable_set(:@children, children)
        CHILD_MEMOS.each { |memo| group.instance_variable_set(memo, nil) }
      end
    end

    def group(example)
      example.example_group.parent_groups.last
    end
  end
end
