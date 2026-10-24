# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/support/warnings"
require "kimera/synthesis/overlay"

# Class-body DSL runs once at load, so its points must go to the isolated oracle.
RSpec.describe(Kimera::Operators) do
  def registry(code, keys)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(code, file: "app.rb")
  end

  # What the block answers with the mutant of that label on.
  def flipped(catalog, label, &) = Kimera::RUNTIME.during(catalog.each.find { |m, _p| m.label == label }.first.id, &)

  describe "rails_permit" do
    let(:permit_src) { <<~RUBY }
      class UsersController
        def user_params
          params.require(:user).permit(:name, :admin)
        end
      end
    RUBY

    it "drops one permitted key per variant", :aggregate_failures do
      catalog = registry(permit_src, ["rails_permit"])
      expect(catalog.each.map { |m, _p| m.label }).to(contain_exactly("permit: drop :name", "permit: drop :admin"))
      expect(catalog.each.map { |_m, p| p.safe? }.uniq).to(eq([true]))
    end

    it "skips splatted allowlists (positions are unknowable)" do
      code = "def p(fields)\n  params.permit(*fields)\nend\n"
      expect(registry(code, ["rails_permit"]).each.count).to(eq(0))
    end

    # Params whose require answers themselves and whose permit answers the keys.
    def fake_params
      Class.new do
        def require(_key) = self
        def permit(*keys) = keys
      end
    end

    # A UsersController from the catalog's overlay, with fake params.
    def controller(catalog)
      stub_const("UsersController", Class.new)
      overlay = Kimera::Overlay.new(catalog).synthesize("app.rb", permit_src)
      Kimera::Warnings::SILENCED.during { TOPLEVEL_BINDING.eval(overlay.source, "app.rb") }
      params = fake_params
      UsersController.new.tap { |users| users.define_singleton_method(:params) { params.new } }
    end

    it "actually narrows the allowlist through a live overlay" do
      catalog = registry(permit_src, ["rails_permit"])
      users = controller(catalog)
      plain = users.user_params
      expect([plain, flipped(catalog, "permit: drop :admin") { users.user_params }]).to(eq([%i[name admin], %i[name]]))
    end
  end

  describe "class-body DSL (rails_validation, rails_callback)" do
    let(:model_src) { <<~RUBY }
      class Signup
        validates :email, presence: true
        before_action :authenticate_user!
        after_commit :notify

        def save
          true
        end
      end
    RUBY

    it "creates points marked for the isolated oracle", :aggregate_failures do
      catalog = registry(model_src, %w[rails_validation rails_callback])
      expect(catalog.each.map { |m, _p| m.label }).to(
        contain_exactly(
          "delete `validates :email, presence: true`",
          "delete `before_action :authenticate_user!`",
          "delete `after_commit :notify`"
        )
      )
      expect(catalog.points.map { |point| [point.safe?, point.body?, point.unsafe_reason] }.uniq)
        .to(eq([[false, true, Kimera::MutationPoint::CLASS_BODY_REASON]]))
    end

    it "matches nothing when only default operators are active" do
      catalog = registry(model_src, Kimera::Operators::DEFAULT_KEYS)
      expect(catalog.each.map { |m, _p| m.label }).not_to(include(a_string_matching(/validates|before_action/)))
    end

    it "bakes the deletion into standalone source for the oracle", :aggregate_failures do
      catalog = registry(model_src, ["rails_validation"])
      id = catalog.each.first.first.id
      baked = Kimera::Overlay.new(catalog).bake("app.rb", model_src, id)
      expect(baked).not_to(include("validates"))
      expect(baked).to(include("before_action")) # only the target was removed
    end

    it "expands the 'rails' group key" do
      built = described_class.build(keys: %w[comparison rails])
      expect(built.map(&:key)).to(
        contain_exactly(
          "comparison", "rails_permit", "rails_validation", "rails_callback",
          "rails_association"
        )
      )
    end
  end

  # R5 (CodeTriage): a PR added `length:` to a validation; deleting the whole call was killed by an old
  # presence test, so the new constraint read as judged while no test exercised it.
  describe "rails_validation option drops" do
    let(:validated_src) { <<~RUBY }
      class Repo
        validates :name, :user_name, presence: true, length: { maximum: 100 }, if: :named?
        validates :email, presence: true
        validates :login, uniqueness: true, allow_nil: true
        validate :sane
      end
    RUBY

    it "drops each option a validates call keeps a validator without", :aggregate_failures do
      labels = registry(validated_src, ["rails_validation"]).each.map { |m, _p| m.label }
      expect(labels).to(
        contain_exactly(
          "delete `validates :name, :user_name, presence: true, length: { maximum: 100 }, if: :named?`",
          "validates: drop presence:", "validates: drop length:", "validates: drop if:",
          "delete `validates :email, presence: true`",
          "delete `validates :login, uniqueness: true, allow_nil: true`", "validates: drop allow_nil:",
          "delete `validate :sane`"
        )
      )
    end

    it "bakes the call without that option for the oracle", :aggregate_failures do
      catalog = registry(validated_src, ["rails_validation"])
      id = catalog.each.find { |m, _p| m.label == "validates: drop length:" }.first.id
      baked = Kimera::Overlay.new(catalog).bake("app.rb", validated_src, id)
      expect(baked).to(include("validates :name, :user_name, presence: true, if: :named?", "validates :email"))
      expect(baked).not_to(include("length:"))
    end
  end

  describe "callback action-scope precision (only:/except:)" do
    let(:scoped_src) { <<~RUBY }
      class PostsController
        before_action :authorize!, only: [:edit, :update]
        after_action :log, except: [:index]
      end
    RUBY

    it "offers one drop per scoped action alongside the whole-filter deletion" do
      catalog = registry(scoped_src, ["rails_callback"])
      expect(catalog.each.map { |m, _p| m.label }).to(
        contain_exactly(
          "delete `before_action :authorize!, only: [:edit, :update]`",
          "before_action: drop :edit from only:",
          "before_action: drop :update from only:",
          "delete `after_action :log, except: [:index]`",
          "after_action: drop :index from except:"
        )
      )
    end

    it "bakes the narrowed action list for the oracle", :aggregate_failures do
      catalog = registry(scoped_src, ["rails_callback"])
      id = catalog.each.find { |m, _p| m.label == "before_action: drop :edit from only:" }.first.id
      baked = Kimera::Overlay.new(catalog).bake("app.rb", scoped_src, id)
      # The other filter is untouched.
      expect(baked).to(include("only: [:update]", "except: [:index]"))
      expect(baked).not_to(include(":edit"))
    end
  end

  describe "rails_association (dependent: deletion)" do
    let(:assoc_src) { <<~RUBY }
      class Author
        has_many :posts, dependent: :destroy
        has_many :drafts, -> { where(published: false) }, dependent: :nullify, inverse_of: :author
        has_one :profile
      end
    RUBY

    it "targets only associations that declare dependent:", :aggregate_failures do
      catalog = registry(assoc_src, ["rails_association"])
      expect(catalog.each.count).to(eq(2))
      catalog.points.each { |point| expect(point.body?).to(be(true)) }
    end

    it "bakes the option away, dropping an emptied options hash entirely", :aggregate_failures do
      catalog = registry(assoc_src, ["rails_association"])
      posts = catalog.each.find { |_m, p| p.original_source.include?(":posts") }.first.id
      baked = Kimera::Overlay.new(catalog).bake("app.rb", assoc_src, posts)
      expect(baked).not_to(include("dependent: :destroy"))
      # No trailing empty hash or comma, and the other one untouched. A splice
      # keeps the call's own spelling, with or without parentheses.
      expect(baked).to(match(/has_many[( ]:posts\)?\s*$/m).and(include("dependent: :nullify")))
    end

    it "keeps sibling options when dropping dependent: from a fuller hash", :aggregate_failures do
      catalog = registry(assoc_src, ["rails_association"])
      drafts = catalog.each.find { |_m, p| p.original_source.include?(":drafts") }.first.id
      baked = Kimera::Overlay.new(catalog).bake("app.rb", assoc_src, drafts)
      expect(baked).not_to(include("dependent: :nullify"))
      expect(baked).to(include("inverse_of: :author"))
    end
  end

  describe "class-body lambda bodies (scopes)" do
    def pricing_code = "class Pricing\n  DISCOUNT = ->(total) { total > 100 ? 10 : 0 }\nend\n"

    def evaluated(source) = Kimera::Warnings::SILENCED.during { TOPLEVEL_BINDING.eval(source, "pricing.rb") }

    def pricing
      stub_const("Pricing", Class.new)
      Kimera::RegistryScan.new(operators: described_class.build(keys: ["comparison"]))
        .source(pricing_code, file: "pricing.rb")
    end

    # > gets its boundary and its swap.
    it "treats lambda bodies as re-executing, schemata-safe code", :aggregate_failures do
      catalog = pricing
      expect(catalog.each.count).to(eq(2))
      expect(catalog.points.map(&:safe?)).to(all(be(true)))
    end

    it "runs a lambda body's mutant live" do
      catalog = pricing
      evaluated(Kimera::Overlay.new(catalog).synthesize("pricing.rb", pricing_code).source)
      plain = Pricing::DISCOUNT.call(100)
      expect([plain, flipped(catalog, "> => >=") { Pricing::DISCOUNT.call(100) }]).to(eq([0, 10]))
    end

    it "still excludes plain do-blocks at class body (run-once DSL)" do
      code = "class M\n  configure do\n    limit > 5\n  end\nend\n"
      catalog = Kimera::RegistryScan.new(operators: described_class.build(keys: ["comparison"]))
        .source(code, file: "m.rb")
      expect(catalog.each.count).to(eq(0))
    end
  end

  describe "class-body matcher gates" do
    it "rails_association only fires in statement position" do
      code = "class Foo\n  x = has_many(:posts, dependent: :destroy)\nend\n"
      expect(registry(code, ["rails_association"]).each.count).to(eq(0))
    end

    it "rails_association skips explicit-receiver calls" do
      code = "class Foo\n  self.has_many :posts, dependent: :destroy\nend\n"
      expect(registry(code, ["rails_association"]).each.count).to(eq(0))
    end

    it "rails_association only matches association macro names" do
      code = "class Foo\n  register :posts, dependent: :destroy\nend\n"
      expect(registry(code, ["rails_association"]).each.count).to(eq(0))
    end

    it "rails_association ignores a string-keyed dependent option" do
      code = "class Foo\n  has_many :posts, \"dependent\" => :destroy\nend\n"
      expect(registry(code, ["rails_association"]).each.count).to(eq(0))
    end

    it "rails_callback only fires in statement position" do
      code = "class Foo\n  x = before_action(:check)\nend\n"
      expect(registry(code, ["rails_callback"]).each.count).to(eq(0))
    end

    it "rails_callback skips explicit-receiver calls" do
      code = "class Foo\n  self.before_action :check\nend\n"
      expect(registry(code, ["rails_callback"]).each.count).to(eq(0))
    end

    it "rails_callback only matches callback macro names" do
      code = "class Foo\n  helper_method :check\nend\n"
      expect(registry(code, ["rails_callback"]).each.count).to(eq(0))
    end

    it "rails_validation only fires in statement position" do
      code = "class Foo\n  x = validates(:email, presence: true)\nend\n"
      expect(registry(code, ["rails_validation"]).each.count).to(eq(0))
    end

    it "rails_validation skips explicit-receiver calls" do
      code = "class Foo\n  self.validates :email, presence: true\nend\n"
      expect(registry(code, ["rails_validation"]).each.count).to(eq(0))
    end

    it "rails_validation only matches validation macro names" do
      code = "class Foo\n  before_action :check\nend\n"
      expect(registry(code, ["rails_validation"]).each.count).to(eq(0))
    end
  end

  describe "callback scope-walk gates" do
    it "steps over a kwsplat among the options", :aggregate_failures do
      code = "class Foo\n  before_action :check, **defaults, only: [:edit]\nend\n"
      catalog = nil
      expect { catalog = registry(code, ["rails_callback"]) }.not_to(raise_error)
      expect(catalog.each.map { |m, _p| m.label }).to(
        contain_exactly(
          "delete `before_action :check, **defaults, only: [:edit]`",
          "before_action: drop :edit from only:"
        )
      )
    end

    it "ignores array options under keys other than only:/except:" do
      code = "class Foo\n  before_action :log, subset: [:index]\nend\n"
      expect(registry(code, ["rails_callback"]).each.map { |m, _p| m.label })
        .to(eq(["delete `before_action :log, subset: [:index]`"]))
    end

    it "ignores a non-array only: value", :aggregate_failures do
      code = "class Foo\n  before_action :log, only: :index\nend\n"
      catalog = nil
      expect { catalog = registry(code, ["rails_callback"]) }.not_to(raise_error)
      expect(catalog.each.map { |m, _p| m.label }).to(eq(["delete `before_action :log, only: :index`"]))
    end

    it "ignores a string-keyed \"only\" option (symbol keys only)" do
      code = "class Foo\n  before_action :log, \"only\" => [:index]\nend\n"
      expect(registry(code, ["rails_callback"]).each.map { |m, _p| m.label })
        .to(eq(["delete `before_action :log, \"only\" => [:index]`"]))
    end
  end
end
