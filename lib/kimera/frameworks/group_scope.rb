# frozen_string_literal: true

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::GroupScope
  def initialize(wanted)
    @wanted = wanted
  end

  def tops = @wanted.map { |example| example.example_group.parent_groups.last }.uniq

  def narrow(filtered, &)
    lineage = @wanted.flat_map { |example| example.example_group.parent_groups }.uniq
    swap(filtered, lineage.to_h { |group| [group, group.examples & @wanted] }) { prune(lineage, &) }
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

  def adopt(families) = families.each { |group, children| group.instance_variable_set(:@children, children) }
end
