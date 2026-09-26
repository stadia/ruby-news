# typed: true

# Self-types for model concerns.
#
# A concern calls methods that its includer provides -- `title_ko` on an
# Article, `fedipub_actor` on a Post -- but nothing in the module says what
# the includer is, so Sorbet resolves `self` to the bare module and reports
# every such call as a missing method.
#
# `requires_ancestor` states the relationship. It belongs here rather than in
# the concern's own source because the source is kept free of Sorbet-specific
# constructs: type information for this project lives in inline `#:` RBS
# comments and in these shims, and RBS has no way to spell a module self-type
# that Sorbet reads.
#
# Each entry is checked: Sorbet verifies the ancestor really is present
# wherever the module is included, so a wrong claim here fails the build rather
# than hiding.
#
# `included do ... end` needs a second declaration. The block is `class_eval`d
# on the includer, so its `self` is that *class*, which `requires_ancestor`
# (a constraint on instances) does not describe -- Sorbet resolves
# `has_many`/`before_save`/`validate` against `T.class_of(TheConcern)` instead.
# Each concern that uses the hook redeclares `included` on its own singleton
# with the includer's class as the block's bind, so the DSL calls inside stay
# checked. A concern bumped to `typed: true` without an entry here fails rather
# than passing unchecked; add one naming its includer.

module Articles::LocalizedDisplay
  extend T::Helpers

  requires_ancestor { Article }
end

module Articles::Activitypub
  extend T::Helpers

  requires_ancestor { Article }
end

module Posts::Federation
  extend T::Helpers

  requires_ancestor { Post }
end

module Posts::Blog
  extend T::Helpers

  requires_ancestor { Post }

  class << self
    sig { params(base: T.untyped, block: T.nilable(T.proc.bind(T.class_of(Post)).void)).returns(T.untyped) }
    def included(base = T.unsafe(nil), &block); end
  end
end

module HtmlSanitizable
  extend T::Helpers

  requires_ancestor { Post }

  class << self
    sig { params(base: T.untyped, block: T.nilable(T.proc.bind(T.class_of(Post)).void)).returns(T.untyped) }
    def included(base = T.unsafe(nil), &block); end
  end
end

# Boost/Like handling is shared by Article and Post, which have no common
# superclass below ActiveRecord::Base -- and `persisted?`, the only thing these
# modules ask of their includer, comes from there anyway.
#
# Their `included` blocks register Fedipub callbacks on an Active Record class.
# Sorbet's `bind` takes a single class name -- no intersection -- so they name
# `Article`, one of the two includers. Post carries the identical surface (both
# models include both concerns), so nothing goes unchecked by the choice.
module FedipubBoostable
  extend T::Helpers

  requires_ancestor { ActiveRecord::Base }

  class << self
    sig do
      params(
        base: T.untyped,
        block: T.nilable(T.proc.bind(T.class_of(Article)).void)
      ).returns(T.untyped)
    end
    def included(base = T.unsafe(nil), &block); end
  end
end

module FedipubLikeable
  extend T::Helpers

  requires_ancestor { ActiveRecord::Base }

  class << self
    sig do
      params(
        base: T.untyped,
        block: T.nilable(T.proc.bind(T.class_of(Article)).void)
      ).returns(T.untyped)
    end
    def included(base = T.unsafe(nil), &block); end
  end
end

# `ClassMethods` modules are `extend`ed, so their `self` is the includer's
# singleton class and `requires_ancestor` (which constrains instances) cannot
# describe it. Both reach for `logger`, declared here as the contract they
# expect -- it is `ActiveRecord::Base.logger` in practice. The includer is a
# class, so `Kernel` (`raise`) is on the chain at runtime too.
module Articles::Activitypub::ClassMethods
  def logger; end
end

module Posts::FederationIngest::ClassMethods
  include Kernel

  def logger; end
end

# Controller concerns name `ApplicationController` rather than the individual
# controllers that include them: what they actually reach for is the inherited
# surface (`render`, `request`, `cookies`, `current_user`), and pinning to a
# single subclass would be both narrower than the truth and wrong the moment a
# second controller includes the module.
module PostViewing
  extend T::Helpers

  requires_ancestor { ApplicationController }
end

module RateLimiting
  extend T::Helpers

  requires_ancestor { ApplicationController }
end

module LocaleSwitcher
  extend T::Helpers

  requires_ancestor { ApplicationController }

  class << self
    sig { params(base: T.untyped, block: T.nilable(T.proc.bind(T.class_of(ApplicationController)).void)).returns(T.untyped) }
    def included(base = T.unsafe(nil), &block); end
  end
end

# Job concerns name `ApplicationJob` rather than the individual jobs that
# include them: what they reach for is the inherited surface (`logger`,
# `raise`, `self.class`), and pinning to a single subclass would be both
# narrower than the truth and wrong the moment a second job includes the module.
module JobRateLimiting
  extend T::Helpers

  requires_ancestor { ApplicationJob }
end

# Not a `requires_ancestor`: DiscordArticlePresenter and SlackArticlePresenter
# both include this and share no superclass, so there is no single ancestor to
# name. They each supply `article`, which is the only thing the module calls on
# its includer -- declared here as the contract the module expects.
module ArticlePresentable
  extend T::Helpers

  def article; end

  # Its `included` block only calls `include`, which every class has, so the bind
  # is `Object` -- the two unrelated presenters have nothing narrower in common.
  class << self
    sig { params(base: T.untyped, block: T.nilable(T.proc.bind(T.class_of(Object)).void)).returns(T.untyped) }
    def included(base = T.unsafe(nil), &block); end
  end
end

# LikesController와 BoostsController가 include한다. 둘 다 ApplicationController를
# 상속하므로 그 인스턴스를 self로 선언하면 `request`/`head`가 해소된다.
# `included` 블록은 `before_action`을 부르므로 바인드를 includer의 클래스로 준다.
module WebOnlyFormats
  extend T::Helpers

  requires_ancestor { ApplicationController }

  class << self
    sig { params(base: T.untyped, block: T.nilable(T.proc.bind(T.class_of(ApplicationController)).void)).returns(T.untyped) }
    def included(base = T.unsafe(nil), &block); end
  end
end

# SlackController와 DiscordController가 include한다. 쓰는 것은 상속받은
# `session`과 `params`뿐이라 ApplicationController를 self로 선언한다.
module OauthStateVerification
  extend T::Helpers

  requires_ancestor { ApplicationController }
end

# SlackController와 DiscordController가 include한다. 상속받은 `params`,
# `logger`, `redirect_to`, `t`와 라우트 헬퍼만 쓰므로 ApplicationController를
# self로 선언한다.
module OauthCallbackFailures
  extend T::Helpers

  requires_ancestor { ApplicationController }
end
