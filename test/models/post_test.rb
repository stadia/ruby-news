# frozen_string_literal: true

require "test_helper"

class PostTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @user = users(:john)
    @root_post = posts(:root_post)
    @reply_post = posts(:reply_post)
    @remote_post = posts(:remote_post)
    @comment_post = posts(:comment_post)
    @article = articles(:ruby_article)
  end

  # ========== Validation Tests ==========

  test "user가 있는 post는 유효하다" do
    post = Post.new(body: "테스트 포스트", user: @user)

    assert_predicate post, :valid?, post.errors.full_messages.join(", ")
  end

  test "fedipub_actor가 있는 post는 유효하다" do
    actor = fedipub_actors(:john_actor)
    post = Post.new(body: "리모트 포스트", fedipub_actor: actor, federated_url: "https://example.com/notes/1")

    assert_predicate post, :valid?, post.errors.full_messages.join(", ")
  end

  test "user도 fedipub_actor도 없으면 유효하지 않다" do
    post = Post.new(body: "고아 포스트")

    assert_not post.valid?
    assert_predicate post.errors[:base], :any?
  end

  test "body는 필수" do
    post = Post.new(user: @user)

    assert_not post.valid?
    assert_predicate post.errors[:body], :any?
  end

  test "body가 빈 문자열이면 유효하지 않다" do
    post = Post.new(body: "", user: @user)

    assert_not post.valid?
  end

  test "human_attribute_name은 locale별 댓글 본문 속성명을 반환해야 한다" do
    I18n.with_locale(:ko) do
      assert_equal "댓글 내용", Post.human_attribute_name(:body)
    end

    I18n.with_locale(:ja) do
      assert_equal "コメント内容", Post.human_attribute_name(:body)
    end
  end

  # ========== Nested Set Tests ==========

  test "root post는 parent가 없다" do
    assert_nil @root_post.parent_id
  end

  test "reply는 parent가 있다" do
    assert_equal @root_post.id, @reply_post.parent_id
  end

  test "root post는 children을 가진다" do
    assert_includes @root_post.children, @reply_post
  end

  # ========== Federation Tests ==========

  test "federation_actor_entity는 user를 반환한다 (로컬)" do
    assert_equal @root_post.user, @root_post.federation_actor_entity
  end

  test "federation_actor_entity는 fedipub_actor를 반환한다 (리모트)" do
    assert_equal @remote_post.fedipub_actor, @remote_post.federation_actor_entity
  end

  test "should_federate?는 entity가 있으면 true" do
    assert_predicate @root_post, :should_federate?
  end

  test "fedipub 좋아요 콜백으로 좋아요와 취소를 처리한다" do
    actor = Fedipub::Actor.create!(
      federated_url: "https://remote.example/users/post-liker-#{SecureRandom.hex(4)}",
      username: "post_liker",
      name: "Post Liker",
      server: "remote.example",
      inbox_url: "https://remote.example/users/post-liker/inbox",
      outbox_url: "https://remote.example/users/post-liker/outbox",
      followers_url: "https://remote.example/users/post-liker/followers",
      followings_url: "https://remote.example/users/post-liker/following",
      profile_url: "https://remote.example/@post-liker",
      actor_type: "Person",
      local: false
    )

    actor_payload = { "id" => actor.federated_url }

    assert_difference -> { Like.where(actor: actor, likeable: @root_post).count }, 1 do
      @root_post.apply_remote_like(actor_payload)
    end

    assert_difference -> { Like.where(actor: actor, likeable: @root_post).count }, -1 do
      @root_post.apply_remote_unlike(actor_payload)
    end
  end

  # ========== Article Comment Tests ==========

  test "comment?는 post_type이 comment이면 true를 반환한다" do
    # 전제 명시: comment? 결과는 픽스처의 post_type 숫자 기본값에 직결된다.
    assert_equal "comment", @comment_post.post_type, "전제: comment_post 픽스처는 post_type=comment"

    assert_predicate @comment_post, :comment?
  end

  test "comment?는 post_type이 short이면 false를 반환한다" do
    assert_equal "short", @root_post.post_type, "전제: root_post 픽스처는 post_type=short"

    assert_not @root_post.comment?
  end

  test "comment?는 post_type이 blog이면 false를 반환한다" do
    assert_equal "blog", posts(:blog_published).post_type, "전제: blog_published 픽스처는 post_type=blog"

    assert_not posts(:blog_published).comment?
  end

  test "comment?는 article_id가 있어도 post_type이 comment가 아니면 false를 반환한다" do
    short_with_article = posts(:short_with_article)

    # 전제 명시: article_id 는 있지만 post_type 이 comment 가 아니라는 조합이 핵심이다.
    assert_predicate short_with_article.article_id, :present?
    assert_equal "short", short_with_article.post_type, "전제: short_with_article 픽스처는 post_type=short"

    assert_not short_with_article.comment?
  end

  test "reply는 parent가 있으면 parent를 반환한다" do
    assert_equal @root_post, @reply_post.reply
  end

  test "reply는 parent가 없고 article이 있으면 article을 반환한다" do
    assert_equal @article, @comment_post.reply
  end

  test "reply는 parent도 article도 없으면 에러를 발생시킨다" do
    post = Post.new(body: "고아 포스트", user: @user)

    error = assert_raises(RuntimeError) { post.reply }
    assert_match(/parent도 article도 없습니다/, error.message)
  end

  test "author_name은 user의 full_name을 반환한다" do
    assert_equal @user.full_name, @root_post.author_name
  end

  test "author_name은 user가 없으면 fedipub_actor의 username을 반환한다" do
    assert_equal @remote_post.fedipub_actor.username, @remote_post.author_name
  end

  test "author_name은 user도 actor도 없으면 익명을 반환한다" do
    post = Post.new(body: "test")

    assert_equal "익명", post.author_name
  end

  test "author_host는 fedipub_actor가 있으면 서버 정보를 반환한다" do
    assert_equal "(#{@remote_post.fedipub_actor.server})", @remote_post.author_host
  end

  test "author_host는 로컬 user가 있으면 nil을 반환한다" do
    assert_nil @root_post.author_host
    assert_nil @comment_post.author_host
  end

  test "author_host는 fedipub_actor가 없으면 nil을 반환한다" do
    assert_nil @root_post.author_host
  end

  # ========== Scope Tests ==========

  test "comments 스코프는 post_type이 comment인 post만 반환한다" do
    comments = Post.comments

    assert_includes comments, @comment_post
    assert_not_includes comments, @root_post
    assert_not_includes comments, posts(:blog_published)
    assert_not_includes comments, posts(:short_with_article)
  end

  test "standalone 스코프는 article_id가 없는 post만 반환한다" do
    standalone = Post.standalone

    assert_includes standalone, @root_post
    assert_not_includes standalone, @comment_post
  end

  # ========== Blog / Enum Tests ==========

  test "post_type enum은 short blog comment를 제공한다" do
    assert_equal %w[short blog comment], Post.post_types.keys
  end

  test "status enum은 draft published를 제공한다" do
    assert_equal %w[draft published], Post.statuses.keys
  end

  test "삭제는 Discard::Model로 처리한다" do
    assert_includes Post.included_modules, Discard::Model
    assert_equal :deleted_at, Post.discard_column
  end

  test "기존 단문은 제목 없이 published short로 유효하다" do
    post = Post.new(body: "단문", user: @user)

    assert_predicate post, :valid?, post.errors.full_messages.join(", ")
    assert_predicate post, :short?
    assert_predicate post, :published?
  end

  test "기사 댓글은 comment 타입으로 지정할 수 있다" do
    post = Post.new(body: "댓글", user: @user, article: @article, post_type: :comment)

    assert_predicate post, :valid?, post.errors.full_messages.join(", ")
    assert_predicate post, :comment?
  end

  test "장문 초안은 제목만 있으면 저장할 수 있다" do
    post = Post.new(title: "초안 제목", body: "", user: @user, post_type: :blog, status: :draft)

    assert_predicate post, :valid?, post.errors.full_messages.join(", ")
  end

  test "장문 초안은 본문만 있으면 저장할 수 있다" do
    post = Post.new(title: "", body: "<p>초안 본문</p>", user: @user, post_type: :blog, status: :draft)

    assert_predicate post, :valid?, post.errors.full_messages.join(", ")
  end

  test "완전히 비어 있는 장문 초안은 유효하지 않다" do
    post = Post.new(title: "", body: "", user: @user, post_type: :blog, status: :draft)

    assert_not post.valid?
    assert_predicate post.errors[:base], :any?
  end

  test "발행 장문은 제목과 본문이 필요하다" do
    missing_title = Post.new(body: "<p>본문</p>", user: @user, post_type: :blog, status: :published)
    missing_body = Post.new(title: "제목", body: "", user: @user, post_type: :blog, status: :published)

    assert_not missing_title.valid?
    assert_predicate missing_title.errors[:title], :any?
    assert_not missing_body.valid?
    assert_predicate missing_body.errors[:body], :any?
  end

  test "published_blog 스코프는 발행된 장문만 반환한다" do
    draft = posts(:blog_draft)
    published = posts(:blog_published)

    assert_includes Post.published_blog, published
    assert_not_includes Post.published_blog, draft
    assert_not_includes Post.published_blog, @root_post
  end

  test "blog_summary는 HTML을 제거하고 앞부분을 반환한다" do
    post = Post.new(body: "<p>Ruby <strong>Rails</strong> 장문입니다.</p>", user: @user, post_type: :blog)

    assert_equal "Ruby Rails 장문입니다.", post.blog_summary
  end

  test "장문은 저장할 때 에디터의 이미지 첨부와 섹션 제목을 유지한다" do
    body = %(<h2>섹션</h2><p>본문</p><action-text-attachment url="https://cdn.example/a.webp" ) +
      %(alt="" caption="설명" content-type="image/*" presentation="gallery"></action-text-attachment>)
    post = Post.create!(title: "장문", body: body, user: @user, post_type: :blog, status: :draft)

    assert_equal %(<h2>섹션</h2><p>본문</p><figure><img src="https://cdn.example/a.webp" alt="설명"><figcaption>설명</figcaption></figure>),
      post.reload.body
  end

  test "단문은 저장할 때 기존 허용 태그로만 정제한다" do
    body = %(<h2>섹션</h2><p>본문</p><action-text-attachment url="https://cdn.example/a.webp" content-type="image/*"></action-text-attachment>)
    post = Post.create!(body: body, user: @user)

    assert_equal "섹션<p>본문</p>", post.reload.body
  end

  test "from_activitypub_object은 기사 답글을 comment 타입으로 지정한다" do
    host = Rails.application.routes.default_url_options[:host]
    hash = {
      "id" => "https://remote.example/notes/comment-1",
      "content" => "기사에 대한 원격 댓글",
      "inReplyTo" => "https://#{host}/articles/#{@article.id}"
    }

    object = Post.from_activitypub_object(hash)

    assert_equal @article.id, object[:article_id]
    assert_equal :comment, object[:post_type]
  end

  test "from_activitypub_object은 기사가 아닌 답글에는 post_type을 지정하지 않는다" do
    hash = {
      "id" => "https://remote.example/notes/standalone-1",
      "content" => "원문 노트"
    }

    object = Post.from_activitypub_object(hash)

    assert_nil object[:post_type]
    assert_nil object[:article_id]
  end

  test "발행된 장문을 discard하면 Delete 활동이 생성된다" do
    published = posts(:blog_published)

    assert_difference -> { Fedipub::Activity.where(action: "Delete", entity: published).count }, 1 do
      published.discard!
    end
  end

  test "발행된 장문을 undiscard하면 Undo 활동이 생성된다" do
    published = posts(:blog_published)
    published.discard!

    assert_difference -> { Fedipub::Activity.where(action: "Undo", entity: published).count }, 1 do
      published.undiscard!
    end
  end

  test "초안 장문을 undiscard해도 Undo 활동이 생성되지 않는다" do
    draft = posts(:blog_draft)
    draft.discard!

    assert_no_difference -> { Fedipub::Activity.where(action: "Undo").count } do
      draft.undiscard!
    end
  end

  # ========== handle_federated_object? Tests ==========

  # ========== Reply Notification Tests ==========

  test "답글 생성 시 ReplyNotificationJob이 큐에 추가된다" do
    other_user = users(:jane)
    assert_enqueued_with(job: ReplyNotificationJob) do
      Post.create!(body: "답글입니다", user: other_user, parent: @root_post)
    end
  end

  test "루트 post 생성 시 ReplyNotificationJob이 큐에 추가되지 않는다" do
    assert_no_enqueued_jobs(only: ReplyNotificationJob) do
      Post.create!(body: "루트 포스트", user: @user)
    end
  end

  test "자기 자신에게 답글 달면 알림이 가지 않는다" do
    assert_no_enqueued_jobs(only: ReplyNotificationJob) do
      Post.create!(body: "셀프 답글", user: @user, parent: @root_post)
    end
  end

  test "parent에 user가 없으면 알림이 가지 않는다" do
    actor = fedipub_actors(:john_actor)
    remote_root = Post.create!(body: "리모트 루트", fedipub_actor: actor, federated_url: "https://remote.example/notes/rr1")
    assert_no_enqueued_jobs(only: ReplyNotificationJob) do
      Post.create!(body: "로컬 답글", user: @user, parent: remote_root)
    end
  end

  # ========== handle_federated_object? Tests ==========

  test "inReplyTo가 없는 Note를 수락한다" do
    hash = { "id" => "https://remote.example.com/notes/plain", "type" => "Note", "content" => "Hello" }

    assert Post.send(:handle_federated_object?, hash)
  end

  test "inReplyTo가 외부 URL이면 거부한다" do
    hash = { "id" => "https://remote.example.com/notes/ext", "type" => "Note", "inReplyTo" => "https://example.com/some/external/post" }

    assert_not Post.send(:handle_federated_object?, hash)
  end

  test "inReplyTo가 로컬 article URL이면 수락한다" do
    local_host = Rails.application.routes.default_url_options[:host] || "www.example.com"
    hash = { "id" => "https://remote.example.com/notes/to-article", "type" => "Note", "inReplyTo" => "http://#{local_host}/articles/#{@article.id}" }

    assert Post.send(:handle_federated_object?, hash)
  end

  test "inReplyTo가 로컬 post를 가리키면 수락한다" do
    local_host = Rails.application.routes.default_url_options[:host] || "www.example.com"
    hash = { "id" => "https://remote.example.com/notes/to-post", "type" => "Note", "inReplyTo" => "http://#{local_host}/posts/#{@root_post.id}" }

    assert Post.send(:handle_federated_object?, hash)
  end

  test "inReplyTo가 리모트 post의 federated_url이면 수락한다" do
    hash = { "id" => "https://remote.example.com/notes/to-remote", "type" => "Note", "inReplyTo" => @remote_post.federated_url }

    assert Post.send(:handle_federated_object?, hash)
  end

  # ========== from_activitypub_object Tests ==========

  test "from_activitypub_object는 body HTML을 유지한다" do
    hash = { "id" => "https://remote.example.com/notes/456", "content" => "<p>Hello <b>world</b></p>" }
    result = Post.from_activitypub_object(hash)

    assert_equal "<p>Hello <b>world</b></p>", result[:body]
    assert_equal "https://remote.example.com/notes/456", result[:federated_url]
  end

  test "from_activitypub_object는 로컬 post URL에서 parent_id를 추출한다" do
    hash = {
      "id" => "https://remote.example.com/notes/999",
      "content" => "로컬 답글",
      "inReplyTo" => "http://example.com/posts/#{@root_post.id}"
    }
    result = Post.from_activitypub_object(hash)

    assert_equal @root_post.id, result[:parent_id]
  end

  test "from_activitypub_object는 기사 댓글을 가리키는 로컬 post URL에서 article_id도 채운다" do
    hash = {
      "id" => "https://remote.example.com/notes/1000",
      "content" => "기사 댓글에 대한 답글",
      "inReplyTo" => "http://example.com/posts/#{@comment_post.id}"
    }
    result = Post.from_activitypub_object(hash)

    assert_equal @comment_post.id, result[:parent_id]
    assert_equal @article.id, result[:article_id]
  end

  test "from_activitypub_object는 inReplyTo로 parent를 찾는다" do
    hash = {
      "id" => "https://remote.example.com/notes/789",
      "content" => "답글",
      "inReplyTo" => @remote_post.federated_url
    }
    result = Post.from_activitypub_object(hash)

    assert_equal @remote_post.id, result[:parent_id]
  end

  test "from_activitypub_object는 article URL에서 article_id를 추출한다" do
    hash = {
      "id" => "https://remote.example.com/notes/art1",
      "content" => "기사 댓글",
      "inReplyTo" => "http://example.com/articles/#{@article.id}"
    }
    result = Post.from_activitypub_object(hash)

    assert_equal @article.id, result[:article_id]
    assert_nil result[:parent_id]
  end

  test "from_activitypub_object는 리모트 UUID article URL의 앞자리 숫자를 article_id로 오인하지 않는다" do
    hash = {
      "id" => "https://hackers.pub/ap/notes/019f4f48-6021-76fa-8193-0dbf3f1a9f40",
      "content" => "리모트 기사에 대한 답글",
      "inReplyTo" => "https://hackers.pub/ap/articles/019f4f28-dc1a-7d42-9e95-2ea7da505e1f"
    }
    result = Post.from_activitypub_object(hash)

    assert_nil result[:article_id]
    assert_nil result[:post_type]
  end

  test "from_activitypub_object는 .jp 로케일 호스트의 article URL도 로컬로 인식한다" do
    hash = {
      "id" => "https://remote.example.com/notes/jp-reply",
      "content" => "일본 로케일 기사 댓글",
      "inReplyTo" => "https://ruby-news.jp/articles/#{@article.id}"
    }
    result = Post.from_activitypub_object(hash)

    assert_equal @article.id, result[:article_id]
    assert_nil result[:parent_id]
  end

  test "from_activitypub_object는 리모트 UUID post URL의 앞자리 숫자를 parent_id로 오인하지 않는다" do
    hash = {
      "id" => "https://hackers.pub/ap/notes/019f4f48-6021-76fa-8193-0dbf3f1a9f40",
      "content" => "리모트 포스트에 대한 답글",
      "inReplyTo" => "https://hackers.pub/ap/posts/019f4f28-dc1a-7d42-9e95-2ea7da505e1f"
    }
    result = Post.from_activitypub_object(hash)

    assert_nil result[:parent_id]
    assert_nil result[:article_id]
  end

  test "from_activitypub_object는 로컬 호스트를 부분문자열로 포함한 원격 호스트를 로컬로 오인하지 않는다" do
    local_host = Rails.application.routes.default_url_options[:host]
    hash = {
      "id" => "https://remote.example.com/notes/spoof",
      "content" => "스푸핑 호스트 답글",
      "inReplyTo" => "https://#{local_host}.attacker.example/articles/#{@article.id}"
    }
    result = Post.from_activitypub_object(hash)

    assert_nil result[:article_id]
    assert_nil result[:parent_id]
  end

  test "from_activitypub_object는 리모트 article URL이 미러링된 post를 가리키면 parent_id로 연결한다" do
    mirrored = Post.create!(
      body: "미러링된 리모트 기사",
      fedipub_actor: fedipub_actors(:john_actor),
      federated_url: "https://hackers.pub/ap/articles/019f4f28-dc1a-7d42-9e95-2ea7da505e1f"
    )
    hash = {
      "id" => "https://hackers.pub/ap/notes/019f4f48-6021-76fa-8193-0dbf3f1a9f40",
      "content" => "리모트 기사에 대한 답글",
      "inReplyTo" => "https://hackers.pub/ap/articles/019f4f28-dc1a-7d42-9e95-2ea7da505e1f"
    }
    result = Post.from_activitypub_object(hash)

    assert_equal mirrored.id, result[:parent_id]
    assert_nil result[:article_id]
  end

  test "from_activitypub_object는 contentMap 본문을 우선 사용한다" do
    hash = {
      "id" => "https://remote.example.com/notes/with-content-map",
      "content" => "",
      "contentMap" => { "ko" => "  로컬라이즈된 본문  " }
    }
    result = Post.from_activitypub_object(hash)

    assert_equal "로컬라이즈된 본문", result[:body]
  end

  test "from_activitypub_object는 첨부만 있는 노트에 폴백 본문을 채운다" do
    hash = {
      "id" => "https://remote.example.com/notes/media-only",
      "content" => "",
      "attachment" => [
        {
          "type" => "Document",
          "url" => "https://remote.example.com/media/image.png",
          "mediaType" => "image/png"
        }
      ]
    }
    result = Post.from_activitypub_object(hash)

    assert_equal I18n.t("posts.remote_attachment_only_body"), result[:body]
    assert_equal 1, result[:media_attachments].size
  end

  test "to_activitypub_object는 parent와 태그와 첨부를 함께 전달한다" do
    post = Post.create!(
      body: "태그와 첨부가 있는 답글",
      user: @user,
      parent: @root_post,
      media_attachments: [ { "url" => "https://example.com/image.png", "mediaType" => "image/png", "name" => "image" } ]
    )
    post.tag_list = "ruby, rails"

    # Pinned to `nil` by the initial assignment otherwise, which rejects the
    # assignment made inside the block below.
    captured = nil #: Hash[Symbol, untyped]?
    Fedipub::DataTransformer::Note.stub(:to_federation, ->(record, content:, name:, custom:) { captured = { record:, content:, name:, custom: }; { "ok" => true } }) do
      post.to_activitypub_object
    end

    assert_equal post, captured[:record]
    assert_equal "태그와 첨부가 있는 답글", captured[:content]
    assert_equal @root_post.federated_url || Rails.application.routes.url_helpers.post_url(@root_post), captured[:custom]["inReplyTo"]
    assert_equal 2, captured[:custom]["tag"].size
    assert_equal "Hashtag", captured[:custom]["tag"].first["type"]
    assert_equal "http://example.com/tag/ruby", captured[:custom]["tag"].first["href"]
    assert_equal "http://example.com/tag/rails", captured[:custom]["tag"].second["href"]
    assert_equal 1, captured[:custom]["attachment"].size
  end

  test "to_activitypub_object는 parent가 없으면 article을 inReplyTo로 사용한다" do
    post = Post.create!(body: "기사 댓글", user: @user, article: @article)

    # Pinned to `nil` by the initial assignment otherwise, which rejects the
    # assignment made inside the block below.
    captured = nil #: Hash[Symbol, untyped]?
    Fedipub::DataTransformer::Note.stub(:to_federation, ->(_record, content:, name:, custom:) { captured = { content:, name:, custom: }; { "ok" => true } }) do
      post.to_activitypub_object
    end

    assert_equal "기사 댓글", captured[:content]
    assert_equal @article.federated_url || Rails.application.routes.url_helpers.article_url(@article), captured[:custom]["inReplyTo"]
  end

  test "federation_reply_recipients는 원격 parent의 actor URL을 반환한다" do
    remote_actor = Fedipub::Actor.create!(
      federated_url: "https://remote.example/users/original",
      username: "original",
      name: "Original",
      server: "remote.example",
      inbox_url: "https://remote.example/users/original/inbox",
      outbox_url: "https://remote.example/users/original/outbox",
      followers_url: "https://remote.example/users/original/followers",
      followings_url: "https://remote.example/users/original/following",
      profile_url: "https://remote.example/@original",
      actor_type: "Person",
      local: false
    )
    remote_root = Post.create!(body: "원격 포스트", fedipub_actor: remote_actor, federated_url: "https://remote.example/notes/456")
    reply = Post.create!(body: "원격 포스트에 대한 답글", user: @user, parent: remote_root)

    assert_equal [ "https://remote.example/users/original" ], reply.federation_reply_recipients
  end

  test "federation_reply_recipients는 로컬 parent인 경우 빈 배열을 반환한다" do
    reply = Post.create!(body: "로컬 포스트에 대한 답글", user: @user, parent: @root_post)

    assert_equal [], reply.federation_reply_recipients
  end

  test "federation_reply_recipients는 parent가 없는 경우 빈 배열을 반환한다" do
    assert_equal [], @root_post.federation_reply_recipients
  end

  test "should_federate?는 user와 actor가 모두 없으면 false를 반환한다" do
    post = Post.new(body: "고아 포스트")

    assert_not post.should_federate?
  end

  test "likes_count는 nil이어도 0을 반환한다" do
    post = Post.new(body: "like count", user: @user)
    post.likers_count = nil

    assert_equal 0, post.likes_count
  end

  test "존재하지 않는 parent_id는 검증 오류를 추가한다" do
    post = Post.new(body: "잘못된 parent", user: @user, parent_id: -999)

    assert_not post.valid?
    assert_includes post.errors[:parent_id], "원본 포스트를 찾을 수 없습니다."
  end

  test "from_activitypub_object는 summary를 본문 폴백으로 사용한다" do
    hash = {
      "id" => "https://remote.example.com/notes/summary-only",
      "summary" => "요약만 있는 본문"
    }

    result = Post.from_activitypub_object(hash)

    assert_equal "요약만 있는 본문", result[:body]
  end

  test "from_activitypub_object는 첨부 이름들을 폴백 본문으로 합친다" do
    hash = {
      "id" => "https://remote.example.com/notes/attachments-with-names",
      "attachment" => [
        { "type" => "Document", "name" => "첫 번째 파일" },
        { "type" => "Image", "name" => "두 번째 파일" }
      ]
    }

    result = Post.from_activitypub_object(hash)

    assert_equal "첫 번째 파일 · 두 번째 파일", result[:body]
  end

  test "to_activitypub_object는 장문을 요약과 제목과 원문 링크로 전달한다" do
    post = posts(:blog_published)

    # Pinned to `nil` by the initial assignment otherwise, which rejects the
    # assignment made inside the block below.
    captured = nil #: Hash[Symbol, untyped]?
    Fedipub::DataTransformer::Note.stub(:to_federation, ->(record, content:, name:, custom:) { captured = { record:, content:, name:, custom: }; { "ok" => true } }) do
      post.to_activitypub_object
    end

    assert_equal post, captured[:record]
    assert_includes captured[:content], post.blog_summary
    assert_includes captured[:content], post.public_url
    assert_equal post.title, captured[:name]
    assert_equal Rails.application.routes.url_helpers.user_profile_blog_post_url(username: post.user.username, slug: post), captured[:custom]["url"]
  end

  test "to_activitypub_object의 실제 발행 Note에 장문 제목이 채워진다" do
    post = Post.create!(
      title: "실제 발행 장문",
      body: "<p>실제 발행되는 장문 본문입니다.</p>",
      user: @user,
      post_type: :blog,
      status: :published,
      published_at: Time.current
    )

    note = post.to_activitypub_object

    assert_equal post.title, note["name"]
    assert_equal "<p>#{post.blog_summary}</p><p><a href=\"#{post.public_url}\">#{post.public_url}</a></p>", note["content"]
    assert_equal Rails.application.routes.url_helpers.user_profile_blog_post_url(username: post.user.username, slug: post), note["url"]
  end

  test "to_activitypub_object는 장문 요약의 HTML 특수문자를 이스케이프한다" do
    post = Post.create!(
      title: "꺾쇠 <b>제목</b>",
      body: "<p>a &lt; b 이고 5 &gt; 3 입니다.</p>",
      user: @user,
      post_type: :blog,
      status: :published,
      published_at: Time.current
    )

    note = post.to_activitypub_object

    assert_includes note["content"], "a &lt; b 이고 5 &gt; 3 입니다."
  end

  # blog_summary는 FullSanitizer 출력이라 엔티티가 디코딩되지 않는다. 본문에
  # 이스케이프된 스크립트 리터럴이 있어도 연합 Note에 실행 가능한 태그로
  # 되살아나지 않아야 한다.
  test "to_activitypub_object는 장문 요약에서 스크립트 태그를 되살리지 않는다" do
    post = Post.create!(
      title: "스크립트 리터럴",
      body: "<p>&lt;script&gt;alert(1)&lt;/script&gt; 예시입니다.</p>",
      user: @user,
      post_type: :blog,
      status: :published,
      published_at: Time.current
    )

    content = post.to_activitypub_object["content"]

    refute_includes content, "<script>"
    assert_includes content, "&lt;script&gt;alert(1)&lt;/script&gt; 예시입니다."
  end

  test "to_activitypub_object는 단문 본문 전체 발행을 유지한다" do
    post = @root_post

    # Pinned to `nil` by the initial assignment otherwise, which rejects the
    # assignment made inside the block below.
    captured = nil #: Hash[Symbol, untyped]?
    Fedipub::DataTransformer::Note.stub(:to_federation, ->(_record, content:, name:, custom:) { captured = { content:, name:, custom: }; { "ok" => true } }) do
      post.to_activitypub_object
    end

    assert_equal post.body, captured[:content]
    assert_nil captured[:name]
    assert_nil captured[:custom]["url"]
    assert_nil captured[:custom]["name"]
  end

  # 초안은 원격에 객체가 없으므로 첫 발행은 Create로 전달해야 한다. publish!는
  # save!가 일으키는 자동 Update를 억제하고 Create를 명시적으로 발행한다.
  test "publish!는 초안 첫 발행 시 Fedipub Create 활동을 발행한다" do
    post = posts(:blog_draft)

    assert_difference -> { Fedipub::Activity.where(action: "Create", entity: post).count }, 1 do
      assert_no_difference -> { Fedipub::Activity.where(action: "Update", entity: post).count } do
        post.publish!
      end
    end
  end

  # 이미 Create를 발행한(원격에 객체가 존재하는) 글의 수정은 일반 Update 경로를
  # 유지한다. Create 승격은 Create 활동이 없는 최초 발행에만 적용된다.
  test "이미 Create가 발행된 글의 수정은 Update 경로를 유지한다" do
    post = posts(:blog_published)
    Fedipub::Activity.create!(actor: fedipub_actors(:john_actor), entity: post, action: "Create")
    post.body = "수정된 본문"

    assert_difference -> { Fedipub::Activity.where(action: "Update", entity: post).count }, 1 do
      assert_no_difference -> { Fedipub::Activity.where(action: "Create", entity: post).count } do
        post.save!
      end
    end
  end

  # discard는 Discard::Model로 처리하고, after_discard에서 Delete를 발행한다.
  test "발행 장문을 discard하면 Delete 활동을 발행한다" do
    post = posts(:blog_published)

    assert_difference -> { Fedipub::Activity.where(action: "Delete", entity: post).count }, 1 do
      post.discard
    end

    assert_predicate post.reload, :discarded?
  end

  # soft_deleted_method: :discarded? 설정으로 삭제된 레코드는 fedipub_tombstoned?가
  # 참이 되어, deleted_at 갱신이 일으키는 일반 Update 활동은 억제된다.
  test "발행 장문을 discard하면 Update 활동은 발행하지 않는다" do
    post = posts(:blog_published)

    assert_no_difference -> { Fedipub::Activity.where(action: "Update", entity: post).count } do
      post.discard
    end
  end

  # 초안은 발행 전까지 로컬에만 머물러야 한다. should_federate?가 published?를
  # 게이트하지 않으면 생성·자동저장마다 미발행 초안이 원격 팔로워에게 새어 나간다.
  test "장문 초안은 생성 시 연합 활동을 발행하지 않는다" do
    assert_no_difference -> { Fedipub::Activity.where(action: [ "Create", "Update" ]).count } do
      @user.posts.create!(post_type: :blog, status: :draft, title: "비공개 초안", body: "")
    end
  end

  test "장문 초안은 자동저장(update) 시 연합 활동을 발행하지 않는다" do
    draft = posts(:blog_draft)

    assert_no_difference -> { Fedipub::Activity.where(entity: draft).count } do
      draft.update!(title: "자동 저장됨", body: "<p>본문</p>")
    end
  end

  test "초안을 발행하면 그때 연합된다" do
    draft = @user.posts.create!(post_type: :blog, status: :draft, title: "초안", body: "<p>본문</p>")

    assert_difference -> { Fedipub::Activity.where(entity: draft).count }, 1 do
      draft.publish!
    end
  end

  # 소프트 삭제는 장문 전용. 인바운드 연합 Delete도 타입별로 분기한다.
  test "인바운드 연합 삭제는 장문을 soft discard한다" do
    post = posts(:blog_published)

    post.run_callbacks(:on_fedipub_delete_requested)

    assert_predicate post.reload, :discarded?
    assert Post.exists?(post.id)
  end

  test "인바운드 연합 삭제는 댓글을 hard destroy한다" do
    post = @comment_post

    post.run_callbacks(:on_fedipub_delete_requested)

    assert_not Post.exists?(post.id)
  end

  # ========== Blog Slug Tests (#1012) ==========

  test "초안 블로그 글은 무작위 slug를 쓴다" do
    draft = @user.posts.create!(post_type: :blog, status: :draft, title: "루비 입문", body: "<p>본문</p>")

    assert_equal 22, draft.slug.length
    assert_not_equal "루비-입문", draft.slug
  end

  test "초안을 발행하면 발행 시점의 제목으로 slug를 만든다" do
    draft = @user.posts.create!(post_type: :blog, status: :draft, title: "첫 제목", body: "<p>본문</p>")
    draft.update!(title: "레일즈 8 — 새 기능!")

    draft.publish!

    assert_equal "레일즈-8-새-기능", draft.reload.slug
  end

  test "초안 없이 바로 발행해도 제목으로 slug를 만든다" do
    post = @user.posts.new(post_type: :blog, title: "바로 발행", body: "<p>본문</p>")

    post.publish!

    assert_equal "바로-발행", post.reload.slug
  end

  test "발행된 글의 제목을 바꿔도 slug는 그대로다" do
    post = @user.posts.new(post_type: :blog, title: "원래 제목", body: "<p>본문</p>")
    post.publish!

    post.update!(title: "바뀐 제목")

    assert_equal "원래-제목", post.reload.slug
  end

  test "기존 무작위 slug로 발행된 글은 제목을 바꿔도 slug가 유지된다" do
    post = posts(:blog_published)

    post.update!(title: "새 제목")

    assert_equal "lf-published-fixture", post.reload.slug
  end

  test "같은 제목·정규화 결과가 같은 제목은 접미사로 slug를 구분한다" do
    first = @user.posts.new(post_type: :blog, title: "Ruby 소식", body: "<p>본문</p>")
    first.publish!
    second = @user.posts.new(post_type: :blog, title: "ruby  소식!!", body: "<p>본문</p>")
    second.publish!

    assert_equal "ruby-소식", first.slug
    assert_match(/\Aruby-소식-[0-9a-z]{#{BlogSlug::SUFFIX_LENGTH}}\z/o, second.reload.slug)
  end

  test "다른 종류의 Post가 쓰는 slug와도 겹치지 않는다" do
    @root_post.update_column(:slug, "겹치는-제목")
    post = @user.posts.new(post_type: :blog, title: "겹치는 제목", body: "<p>본문</p>")

    post.publish!

    assert_not_equal "겹치는-제목", post.reload.slug
    assert post.slug.start_with?("겹치는-제목-")
  end

  test "숫자만 있는 제목은 id 조회와 헷갈리지 않도록 접미사를 붙인다" do
    post = @user.posts.new(post_type: :blog, title: "2026", body: "<p>본문</p>")

    post.publish!

    assert_match(/\A2026-[0-9a-z]+\z/, post.reload.slug)
  end

  test "긴 제목도 slug 길이 제한 안에서 저장된다" do
    post = @user.posts.new(post_type: :blog, title: "가" * 255, body: "<p>본문</p>")

    post.publish!

    assert_equal "가" * BlogSlug::BASE_MAX_LENGTH, post.reload.slug
  end

  test "특수문자만 있는 제목은 무작위 slug로 대체한다" do
    post = @user.posts.new(post_type: :blog, title: "!!! ??? 🎉", body: "<p>본문</p>")

    post.publish!

    assert_equal 22, post.reload.slug.length
  end

  test "발행 검증이 실패하면 slug를 저장된 값으로 되돌린다" do
    draft = posts(:blog_draft)
    draft.title = ""

    assert_raises(ActiveRecord::RecordInvalid) { draft.publish! }
    assert_equal "lf-draft-fixture", draft.slug
  end

  test "단문 포스트는 무작위 slug를 유지한다" do
    post = @user.posts.create!(body: "단문 포스트", title: "제목이 있는 단문")

    assert_equal 22, post.slug.length
  end

  test "posts.slug 컬럼은 길이 제한 없는 text이고 길이는 BlogSlug가 정한다" do
    column = Post.columns_hash["slug"]

    assert_equal :text, column.type
    assert_nil column.limit
    @root_post.update_column(:slug, "가" * (BlogSlug::MAX_LENGTH + 1))

    assert_equal BlogSlug::MAX_LENGTH + 1, @root_post.reload.slug.length
  end

  test "posts.slug의 유니크 인덱스가 중복 slug를 막는다" do
    @root_post.update_column(:slug, "중복-slug")

    assert_raises(ActiveRecord::RecordNotUnique) do
      @reply_post.update_column(:slug, "중복-slug")
    end
  end
end
