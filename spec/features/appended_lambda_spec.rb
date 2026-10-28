# frozen_string_literal: true

# R6B2-M5: the warm overlay evaluates a mutated file again, so a class-body
# macro that adds to a list (ActiveRecord's default_scope) holds the original
# lambda and the woven one. A test reaches the woven one, and the original
# masks its mutant: places-manager's `default_scope -> { order(name: :asc) }`
# survived warm, deleted, and failed three examples baked.
RSpec.describe("a lambda a class-body macro adds to a list") do
  def files = {
    "app/item.rb" => <<~RUBY,
      # frozen_string_literal: true
      class Item
        def self.scopes = (@scopes ||= [])

        def self.default_scope(body) = scopes << body

        def self.all(names) = scopes.reduce(names) { |list, scope| scope.call(list) || list }

        default_scope ->(list) { list.sort }
      end
    RUBY
    "spec/item_spec.rb" => <<~RUBY
      # frozen_string_literal: true
      require_relative "../app/item"

      RSpec.describe Item do
        it("lists by name") { expect(Item.all(%w[b a])).to eq(%w[a b]) }
      end
    RUBY
  }

  it "judges a warm survivor of the lambda again in a fresh mirror, where the suite kills it" do
    run = test_tree(files, "kimera-appended") { |tree| test_outcome(cwd: tree, arguments: ["--no-gate"]) }
    sorted = run.results.find { |row| row["original"] == "list.sort" }
    expect(sorted.values_at("status", "failing_tests")).to(eq(["killed", ["./spec/item_spec.rb[1:1]"]]), run.output)
  end
end
