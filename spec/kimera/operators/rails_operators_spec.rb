# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/synthesis/overlay"

# Class-body DSL runs once at load, so its points must go to the isolated oracle.
RSpec.describe("rails operators") do
  def registry(src, keys)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(src, file: "app.rb")
  end

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
      src = "def p(fields)\n  params.permit(*fields)\nend\n"
      expect(registry(src, ["rails_permit"]).each.count).to(eq(0))
    end

    it "actually narrows the allowlist through a live overlay", :aggregate_failures do
      catalog = registry(permit_src, ["rails_permit"])
      result = Kimera::Overlay.new(catalog).synthesize("app.rb", permit_src)
      fake_params =
        Class.new do
          def require(_key) = self
          def permit(*keys) = keys
        end
      verbose = $VERBOSE
      $VERBOSE = nil
      TOPLEVEL_BINDING.eval(result.source, "app.rb")
      $VERBOSE = verbose

      controller = UsersController.new
      controller.define_singleton_method(:params) { fake_params.new }
      expect(controller.user_params).to(eq(%i[name admin]))

      mutant = catalog.each.find { |m, _p| m.label == "permit: drop :admin" }.first.id
      Kimera::RUNTIME.active = mutant
      expect(controller.user_params).to(eq(%i[name]))
    ensure
      Kimera::RUNTIME.reset!
      Object.__send__(:remove_const, :UsersController) if defined?(UsersController)
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
      labels = catalog.each.map { |m, _p| m.label }
      expect(labels).to(
        contain_exactly(
          "delete `validates :email, presence: true`",
          "delete `before_action :authenticate_user!`",
          "delete `after_commit :notify`"
        )
      )
      catalog.points.each do |point|
        expect(point.safe?).to(be(false))
        expect(point.body?).to(be(true))
        expect(point.unsafe_reason).to(eq(Kimera::MutationPoint::CLASS_BODY_REASON))
      end
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
      built = Kimera::Operators.build(keys: %w[comparison rails])
      expect(built.map(&:key)).to(
        contain_exactly(
          "comparison", "rails_permit", "rails_validation", "rails_callback",
          "rails_association"
        )
      )
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
      expect(baked).to(include("only: [:update]"))
      expect(baked).not_to(include(":edit"))
      expect(baked).to(include("except: [:index]")) # the other filter is untouched
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
      expect(baked).to(match(/has_many\(?:posts\)?\s*$/m)) # no trailing empty hash
      expect(baked).to(include("dependent: :nullify"))     # the other one untouched
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
    it "treats lambda bodies as re-executing, schemata-safe code", :aggregate_failures do
      src = <<~RUBY
        class Pricing
          DISCOUNT = ->(total) { total > 100 ? 10 : 0 }
        end
      RUBY
      catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["comparison"]))
        .source(src, file: "pricing.rb")
      expect(catalog.each.count).to(eq(2)) # > gets its boundary + swap
      catalog.points.each { |point| expect(point.safe?).to(be(true)) }

      result = Kimera::Overlay.new(catalog).synthesize("pricing.rb", src)
      verbose = $VERBOSE
      $VERBOSE = nil
      TOPLEVEL_BINDING.eval(result.source, "pricing.rb")
      $VERBOSE = verbose

      expect(Pricing::DISCOUNT.call(100)).to(eq(0))
      boundary = catalog.each.find { |m, _p| m.label == "> => >=" }.first.id
      Kimera::RUNTIME.active = boundary
      expect(Pricing::DISCOUNT.call(100)).to(eq(10))
    ensure
      Kimera::RUNTIME.reset!
      Object.__send__(:remove_const, :Pricing) if defined?(Pricing)
    end

    it "still excludes plain do-blocks at class body (run-once DSL)" do
      src = "class M\n  configure do\n    limit > 5\n  end\nend\n"
      catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["comparison"]))
        .source(src, file: "m.rb")
      expect(catalog.each.count).to(eq(0))
    end
  end

  describe "class-body matcher gates" do
    it "rails_association only fires in statement position" do
      src = "class Foo\n  x = has_many(:posts, dependent: :destroy)\nend\n"
      expect(registry(src, ["rails_association"]).each.count).to(eq(0))
    end

    it "rails_association skips explicit-receiver calls" do
      src = "class Foo\n  self.has_many :posts, dependent: :destroy\nend\n"
      expect(registry(src, ["rails_association"]).each.count).to(eq(0))
    end

    it "rails_association only matches association macro names" do
      src = "class Foo\n  register :posts, dependent: :destroy\nend\n"
      expect(registry(src, ["rails_association"]).each.count).to(eq(0))
    end

    it "rails_association ignores a string-keyed dependent option" do
      src = "class Foo\n  has_many :posts, \"dependent\" => :destroy\nend\n"
      expect(registry(src, ["rails_association"]).each.count).to(eq(0))
    end

    it "rails_callback only fires in statement position" do
      src = "class Foo\n  x = before_action(:check)\nend\n"
      expect(registry(src, ["rails_callback"]).each.count).to(eq(0))
    end

    it "rails_callback skips explicit-receiver calls" do
      src = "class Foo\n  self.before_action :check\nend\n"
      expect(registry(src, ["rails_callback"]).each.count).to(eq(0))
    end

    it "rails_callback only matches callback macro names" do
      src = "class Foo\n  helper_method :check\nend\n"
      expect(registry(src, ["rails_callback"]).each.count).to(eq(0))
    end

    it "rails_validation only fires in statement position" do
      src = "class Foo\n  x = validates(:email, presence: true)\nend\n"
      expect(registry(src, ["rails_validation"]).each.count).to(eq(0))
    end

    it "rails_validation skips explicit-receiver calls" do
      src = "class Foo\n  self.validates :email, presence: true\nend\n"
      expect(registry(src, ["rails_validation"]).each.count).to(eq(0))
    end

    it "rails_validation only matches validation macro names" do
      src = "class Foo\n  before_action :check\nend\n"
      expect(registry(src, ["rails_validation"]).each.count).to(eq(0))
    end
  end

  describe "callback scope-walk gates" do
    it "steps over a kwsplat among the options", :aggregate_failures do
      src = "class Foo\n  before_action :check, **defaults, only: [:edit]\nend\n"
      catalog = nil
      expect { catalog = registry(src, ["rails_callback"]) }.not_to(raise_error)
      expect(catalog.each.map { |m, _p| m.label }).to(
        contain_exactly(
          "delete `before_action :check, **defaults, only: [:edit]`",
          "before_action: drop :edit from only:"
        )
      )
    end

    it "ignores array options under keys other than only:/except:" do
      src = "class Foo\n  before_action :log, subset: [:index]\nend\n"
      expect(registry(src, ["rails_callback"]).each.map { |m, _p| m.label })
        .to(eq(["delete `before_action :log, subset: [:index]`"]))
    end

    it "ignores a non-array only: value", :aggregate_failures do
      src = "class Foo\n  before_action :log, only: :index\nend\n"
      catalog = nil
      expect { catalog = registry(src, ["rails_callback"]) }.not_to(raise_error)
      expect(catalog.each.map { |m, _p| m.label }).to(eq(["delete `before_action :log, only: :index`"]))
    end

    it "ignores a string-keyed \"only\" option (symbol keys only)" do
      src = "class Foo\n  before_action :log, \"only\" => [:index]\nend\n"
      expect(registry(src, ["rails_callback"]).each.map { |m, _p| m.label })
        .to(eq(["delete `before_action :log, \"only\" => [:index]`"]))
    end
  end
end
