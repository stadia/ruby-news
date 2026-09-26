# typed: true
# rbs_inline: disabled

# This file is hand-written RBI (Sorbet `sig` DSL), not Ruby source -- RBS
# inline (`#:`) annotations don't apply, so RBS inline generation is off.

# Constants that the generated gem RBIs do not cover.

# Fedipub ships its policies as engine-autoloaded files under app/policies,
# so `tapioca gem` -- which only reflects over what `require` loads -- never
# sees Fedipub::FedipubPolicy. Its subclasses in the generated RBI then
# point at an unresolved parent, and inherited lookups like
# Fedipub::Client::ActivityPolicy::Scope fail.
module Fedipub
  class FedipubPolicy
    class Scope; end
  end

  module Client
    # ActivityPolicy inherits Scope rather than defining it, so the generated
    # RBI has no entry for it -- unlike its siblings (ActorPolicy::Scope,
    # FollowingPolicy::Scope), which the gem declares outright. Referenced by
    # ActivitiesController#index.
    class ActivityPolicy::Scope < ::Fedipub::FedipubPolicy::Scope; end
  end
end

# `friendly` is added at runtime, which Sorbet can't resolve statically -- but
# for two different reasons on the model vs. the relation:
#  - Model (class << self): `extend FriendlyId` installs `friendly` through a
#    `self.extended` hook that Tapioca does not trace, so the generated RBI
#    omits it.
#  - Relation: it is *not* FriendlyId but `ActiveRecord::Delegation` forwarding
#    the model's singleton method, and Tapioca's model RBI does not project
#    that onto Article's generated relation classes.
class Article
  class << self
    sig { returns(PrivateRelation) }
    def friendly; end
  end

  class PrivateRelation
    sig { returns(PrivateRelation) }
    def friendly; end
  end
end

# `friendly_id` and `after_discard`/`after_undiscard` are class methods
# installed by `extend FriendlyId` and `include Discard::Model` respectively.
# Tapioca does not reflect over these hooks (same mechanism as `friendly`
# above), so Sorbet reports them as missing on every model that uses them.
# Declared per-model because Sorbet does not project `included`-hook singleton
# methods onto their includers.
class Article
  class << self
    sig { params(args: T.untyped, kwargs: T.untyped).void }
    def friendly_id(*args, **kwargs); end

    sig { params(name: T.nilable(T.any(Symbol, String)), args: T.untyped, kwargs: T.untyped, block: T.nilable(T.proc.void)).void }
    def after_discard(name = nil, *args, **kwargs, &block); end

    sig { params(name: T.nilable(T.any(Symbol, String)), args: T.untyped, kwargs: T.untyped, block: T.nilable(T.proc.void)).void }
    def after_undiscard(name = nil, *args, **kwargs, &block); end
  end
end

class Post
  class << self
    sig { params(args: T.untyped, kwargs: T.untyped).void }
    def friendly_id(*args, **kwargs); end

    sig { params(name: T.nilable(T.any(Symbol, String)), args: T.untyped, kwargs: T.untyped, block: T.nilable(T.proc.void)).void }
    def after_discard(name = nil, *args, **kwargs, &block); end

    sig { params(name: T.nilable(T.any(Symbol, String)), args: T.untyped, kwargs: T.untyped, block: T.nilable(T.proc.void)).void }
    def after_undiscard(name = nil, *args, **kwargs, &block); end
  end
end

# `friendly_id ..., use: :slugged`는 런타임에 FriendlyId::Slugged를 include한다.
# Post는 normalize_friendly_id를 재정의해 super를 부르므로 그 include 엣지만
# 선언한다. 메서드 본체는 `friendly_id@5.7.0.rbi`에 있다.
class Post
  include FriendlyId::Slugged
end

# `devise` 매크로는 런타임에 모듈을 mixin하므로, 생성된 User RBI에는 그
# include 엣지가 없다. 메서드 본체는 `devise@5.0.4.rbi`에 이미 있으므로
# 손으로 재선언하지 않고 include/extend만 선언한다. Confirmable 전체를
# 커버하고 Devise 업그레이드 시 시그니처를 자동 추종한다. (`friendly_id`
# 블록과 달리, 여기는 메서드 본체가 존재하는 RBI에 이미 있는 케이스다.)
class User
  include Devise::Models::Confirmable
  extend Devise::Models::Confirmable::ClassMethods
end

# Devise controllers inherit `resource_class` typed as `T::Class[T.anything]`,
# so the Confirmable class methods on the resource are unresolvable. The
# resource for this controller is always `User`, so narrow the return type.
# Scoped to this controller on purpose: if another mapping (e.g.
# `devise_for :admins`) is added, its controller must get its own shim
# rather than inheriting a `User`-only narrowing.
module Users
  class ConfirmationsController
    sig { returns(T.class_of(User)) }
    def resource_class; end
  end
end

# The `herb` gem is excluded from `tapioca gem` (see sorbet/tapioca/config.yml),
# but reactionview's RBI subclasses Herb::Engine.
module Herb
  class Engine; end
end

# Bundler 4 vendors connection_pool as Bundler::ConnectionPool, whose
# ForkTracker extends Process at runtime. `tapioca gem` records that extend in
# the sqlite3 and test-prof RBIs, but no gem RBI defines the vendored module.
module Bundler
  module ConnectionPool
    module ForkTracker; end
  end
end
