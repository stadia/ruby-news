# typed: true

# Gem DSL blocks whose `self` is rebound at runtime.
#
# `tapioca gem` records these methods as taking a plain `&block`, so Sorbet
# resolves calls inside the block against the *enclosing* class -- reporting
# every DSL call as "method does not exist". Redeclaring the method with a
# `T.proc.bind(...)` block tells Sorbet what `self` actually is inside.
#
# Keep each entry in sync with the generated RBI it overrides: same parameter
# names and arity, or Sorbet reports a redefinition mismatch instead.

module Alba::Resource::ClassMethods
  # lib/alba/resource.rb -- `attribute :x do |obj| ... end` blocks are
  # `instance_exec`d on the resource *instance* during serialization, which is
  # where `params` (and `object`) live. Without the bind Sorbet resolves
  # `params` against the serializer's singleton class.
  #
  # The yielded object stays `T.untyped` here because a resource class is not
  # bound to one model; the serializers below narrow it to theirs.
  sig do
    params(
      name: T.untyped,
      if: T.untyped,
      name_with_type: T.untyped,
      block: T.nilable(T.proc.bind(Alba::Resource::InstanceMethods).params(arg0: T.untyped).returns(T.untyped))
    ).returns(T.untyped)
  end
  def attribute(name = T.unsafe(nil), if: T.unsafe(nil), **name_with_type, &block); end
end

# Each serializer knows the model it yields, so it narrows `attribute`'s block
# parameter -- without this the block body reads an untyped object and typos like
# `article.tites` pass. `object` is the same model, so it is declared too.
class ArticleSerializer
  class << self
    sig do
      params(
        name: T.untyped,
        if: T.untyped,
        name_with_type: T.untyped,
        block: T.nilable(T.proc.bind(Alba::Resource::InstanceMethods).params(arg0: Article).returns(T.untyped))
      ).returns(T.untyped)
    end
    def attribute(name = T.unsafe(nil), if: T.unsafe(nil), **name_with_type, &block); end
  end

  sig { returns(Article) }
  def object; end
end

class PostSerializer
  class << self
    sig do
      params(
        name: T.untyped,
        if: T.untyped,
        name_with_type: T.untyped,
        block: T.nilable(T.proc.bind(Alba::Resource::InstanceMethods).params(arg0: Post).returns(T.untyped))
      ).returns(T.untyped)
    end
    def attribute(name = T.unsafe(nil), if: T.unsafe(nil), **name_with_type, &block); end
  end

  sig { returns(Post) }
  def object; end
end

class RubyLLM::Agent
  class << self
    # lib/ruby_llm/agent.rb -- a non-lambda `schema { ... }` block becomes
    # Schematist::Schema.create(&block), which class_evals it on an anonymous
    # Schematist::Schema subclass. That is where `string`/`array`/`object`/
    # `integer`/`number`/`boolean` live.
    #
    # Used by app/agents/*.rb.
    sig do
      params(
        value: T.untyped,
        block: T.nilable(T.proc.bind(T.class_of(Schematist::Schema)).void)
      ).returns(T.untyped)
    end
    def schema(value = nil, &block); end
  end
end

module Mail
  class << self
    # lib/mail/mail.rb -- `Mail.defaults { ... }` instance_eval's the block on
    # the Mail::Configuration singleton, which is where `retriever_method` and
    # `delivery_method` live.
    #
    # Used by app/clients/gmail.rb.
    sig { params(block: T.proc.bind(::Mail::Configuration).void).returns(T.untyped) }
    def defaults(&block); end
  end
end

class Madmin::Resource
  class << self
    # lib/madmin/resource.rb -- the block is stored as a `Madmin::MemberAction`
    # and `instance_exec`d on the show view's context
    # (madmin's app/views/madmin/application/show.html.erb), which is where
    # `button_to`, `safe_join` and the `*_madmin_*_path` route helpers live.
    #
    # `HelperProxy` is tapioca's model of that context: it subclasses
    # ActionView::Base and includes GeneratedPathHelpersModule.
    #
    # The yielded record stays `T.untyped` -- `Madmin::Resource` is not bound to
    # one model, and the blocks in app/madmin/resources narrow it themselves
    # with `record.is_a?(...)`.
    sig do
      params(
        collection: T.untyped,
        block: T.proc.bind(::Madmin::ResourceController::HelperProxy).params(arg0: T.untyped).returns(T.untyped)
      ).returns(T.untyped)
    end
    def member_action(collection: T.unsafe(nil), &block); end
  end
end
