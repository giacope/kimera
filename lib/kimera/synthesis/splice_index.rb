# frozen_string_literal: true

# A source's tree as a splice reads it: each node by its span and type, each
# node's parent, and the lines a heredoc opens on.
class Kimera::SpliceIndex
  def initialize(root)
    @root = root
  end

  def node(point) = anchors[[point.location.start_offset, point.location.finish, point.node_type]]

  def parent(node) = parents[node]

  def heredoc?(node) = heredocs.intersect?(node.location.start_line..node.location.end_line)

  private

  def anchors = @_anchors ||= nodes.to_h { |node, _| [anchor(node), node] }

  def anchor(node) = [node.location.start_offset, node.location.end_offset, node.type.to_s]

  def parents = @_parents ||= nodes.select(&:last).to_h.compare_by_identity

  def heredocs = @_heredocs ||= nodes.filter_map { |node, _| node.location.start_line if opens?(node) }.to_set

  def opens?(node) = node.respond_to?(:heredoc?) && node.heredoc?

  def nodes = @_nodes ||= walk(@root, nil)

  def walk(node, parent) = [[node, parent], *node.compact_child_nodes.flat_map { |child| walk(child, node) }]
end
