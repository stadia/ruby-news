# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# Inbound ActivityPub parsing for Post: turns a remote Note hash into local
# attributes, resolving the reply target (article comment, post reply, or
# federated parent) and extracting body/attachments/hashtags.
#
# Symmetric to the outbound serialization in Posts::Federation. Kept out of Post
# itself so the model stays focused on persistence, enums, scopes, and callbacks.
module Posts::FederationIngest
  extend ActiveSupport::Concern

  class_methods do
    #: (Hash[String, untyped]) -> Hash[Symbol, untyped]
    def from_activitypub_object(hash)
      in_reply_to = hash["inReplyTo"].to_s

      # 이중 방어선. id 없는 객체는 handle_federated_object? 에서 이미 거부되므로
      # 여기 도달하면 인박스 필터를 우회한 호출이다(직접 호출 또는 필터 회귀).
      # 그대로 두면 federated_url 이 nil 인 채로 진행되어, fedipub 의
      # `find_by federated_url: nil` 이 무관한 로컬 post 를 매칭한다.
      logger.warn { "from_activitypub_object: id-less object bypassed the inbox filter (inReplyTo=#{in_reply_to.truncate(200).inspect})" } if hash["id"].blank?

      attachments = Array.wrap(hash["attachment"]).select { |a| a.is_a?(Hash) && (a["type"] == "Document" || a["type"] == "Image") }

      object = {
        federated_url: hash["id"],
        url: hash["url"],
        title: hash["summary"].presence,
        body: extract_body_from_activitypub_object(hash, attachments:)
      }

      object.merge!(reply_attributes(in_reply_to)) if in_reply_to.present?

      # Mastodon 이미지 첨부 파싱
      object[:media_attachments] = attachments.map do |a|
        { "url" => a["url"], "mediaType" => a["mediaType"], "name" => a["name"] }.compact
      end

      # Mastodon 해시태그 파싱
      hashtags = Array.wrap(hash["tag"]).select { |t| t.is_a?(Hash) && t["type"] == "Hashtag" }
      object[:tag_list] = hashtags.map { |t| t["name"].to_s.delete_prefix("#") }.uniq.join(", ") if hashtags.any?

      object
    end

    private

    # Resolves the reply target (article comment, post reply, or federated
    # parent) from an inReplyTo URL into attributes for from_activitypub_object.
    # Inbound replies to an article are typed :comment so they stay in the
    # `comments` scope instead of defaulting to :short.
    #: (String) -> Hash[Symbol, untyped]
    def reply_attributes(in_reply_to)
      attrs = reply_target_attributes(in_reply_to)
      return attrs if attrs[:article_id].blank?

      attrs.merge(post_type: :comment)
    end

    # 모든 분기가 Integer id를 돌려준다: 정규식 캡처(String)와 DB 컬럼(Integer)이
    # 섞이면 호출부에서 타입이 갈리므로 여기서 정규화한다.
    # 부모가 있으면 article_id 키를 nil이라도 항상 담는다. fedipub은 이 해시를
    # Update 수신·원격 재동기화에서 assign_attributes/update!로도 쓰므로, 키를
    # 빼면 답글에 낡은 article_id가 남는다.
    #: (String) -> Hash[Symbol, untyped]
    def reply_target_attributes(in_reply_to)
      if local_reply_target?(in_reply_to)
        target = local_reply_target(in_reply_to)
        unless target
          logger.warn { "reply_target_attributes: missing local inReplyTo #{in_reply_to.inspect}; refusing to store as standalone" }
          raise ActiveRecord::RecordNotFound, "Local reply target not found: #{in_reply_to.truncate(200)}"
        end

        return { article_id: target.id } if target.is_a?(Article)

        return { parent_id: target.id, article_id: target.article_id }
      end

      if (parent = Post.find_by(federated_url: in_reply_to))
        { parent_id: parent.id, article_id: parent.article_id }
      else
        # Unresolved inReplyTo: stored standalone — orphan은 프로덕션에서도
        # 보여야 하므로 debug가 아니라 warn으로 남긴다.
        logger.warn { "reply_target_attributes: unresolved inReplyTo #{in_reply_to.inspect}; storing reply without parent/article" }
        {}
      end
    end

    # Only routes we publish or serve locally may resolve to a local target.
    # The public post/article routes use slugs; fedipub's published routes use IDs.
    #: (String) -> (Post | Article)?
    def local_reply_target(in_reply_to)
      path = URI.parse(in_reply_to).path

      case path
      when %r{\A/federation/published/posts/(\d+)/?\z}
        Post.find_by(id: Regexp.last_match(1))
      when %r{\A/federation/published/articles/(\d+)/?\z}
        Article.find_by(id: Regexp.last_match(1))
      when %r{\A/posts/([^/.]+)(?:\.html)?/?\z}
        find_by_slug_or_id(Post, Regexp.last_match(1).to_s)
      when %r{\A/articles/([^/.]+)(?:\.(?:html|md))?/?\z}
        find_by_slug_or_id(Article, Regexp.last_match(1).to_s)
      end
    end

    # 퍼센트 디코딩 결과가 잘못된 UTF-8이거나 NUL을 품으면 PG가 쿼리 자체를
    # 거부해(StatementInvalid/ArgumentError) 인박스가 500을 낸다. 그런 slug는
    # 존재할 수 없으므로 조회하지 않고 대상 없음으로 돌려 404 경로에 합친다.
    #: (singleton(Post) | singleton(Article), String) -> (Post | Article)?
    def find_by_slug_or_id(model, escaped_identifier)
      identifier = URI::DEFAULT_PARSER.unescape(escaped_identifier)
      return unless identifier.valid_encoding? && !identifier.include?("\0")

      model.find_by(slug: identifier) || (model.find_by(id: identifier) if identifier.match?(/\A\d+\z/))
    end

    # Exact host match, not substring: a URL merely embedding a local host
    # (ruby-news.dev.attacker.example) must not count as local. The app serves
    # both locale hosts, so Hosts.local_host? is authoritative; the configured
    # routing host is a fallback for envs served elsewhere (test on example.com).
    # 비어 있는 routing host는 부팅 시점에 막는다(config/initializers/routes_default_host.rb).
    # 호출부는 로컬 여부만 구별하므로 bool로 돌려주고, 파싱 불가 같은 실패 모드는
    # 로그로만 드러낸다.
    #: (String) -> bool
    def local_reply_target?(in_reply_to)
      host = URI.parse(in_reply_to).host
      return false if host.blank?

      # Hosts.local_host? 와 같은 이유로 대소문자 비구분 비교 (호스트명은 DNS 규격상
      # 대소문자를 구분하지 않고 URI.parse 는 입력 대소문자를 보존한다).
      Hosts.local_host?(host) || host.casecmp?(Rails.application.routes.default_url_options[:host].to_s)
    rescue URI::InvalidURIError => e
      # 파싱 불가 URL은 원격으로 처리되지만, 조용히 삼키면 잘못된 발신자를
      # 추적할 수 없다.
      logger.warn { "local_reply_target?: unparseable inReplyTo #{in_reply_to.inspect}: #{e.message}" }
      false
    end

    # 본문 우선순위 체인 (앞쪽이 이길수록 원문에 가깝다):
    #   1. contentMap의 첫 비어있지 않은 값 — 발신 서버가 로케일별 본문을 준
    #      경우로, 언어 협상 없이 순서대로 첫 값을 쓴다(Mastodon은 보통 1개).
    #   2. content — 단일 본문 필드. 대다수 노트가 여기서 끝난다.
    #   3. summary — 본문이 비고 CW(콘텐츠 경고)만 있는 노트 구제용.
    #   4. 첨부 이름을 " · "로 결합 — 이미지만 있는 노트가 빈 본문으로 남지
    #      않게 alt/파일명이라도 보여준다.
    #   5. I18n sentinel — 위 전부가 비었을 때의 최종 폴백. Post는 body presence를
    #      검증하므로(draft 장문 제외) 빈 문자열을 돌려주면 인바운드 저장이 실패한다.
    #: (Hash[String, untyped], attachments: Array[Hash[String, untyped]]) -> String
    def extract_body_from_activitypub_object(hash, attachments:)
      localized_content = hash["contentMap"]
        .then { |content_map| content_map.is_a?(Hash) ? content_map.values : [] }
        .filter_map { |value| value.to_s.squish.presence }
        .first

      body = localized_content || hash["content"].to_s.squish.presence || hash["summary"].to_s.squish.presence
      return body if body.present?

      attachment_names = attachments.filter_map { |attachment| attachment["name"].to_s.squish.presence }
      attachment_names.join(" · ").presence || I18n.t("posts.remote_attachment_only_body")
    end

    #: (Hash[String, untyped]) -> bool
    def handle_federated_object?(hash)
      # id 없는 객체는 수락 자체를 거부한다. fedipub 는 엔티티를
      # `find_by federated_url: hash['id']` 로 찾는데(utils/object.rb), 로컬 post 는
      # 전부 federated_url 이 NULL 이다(젬의 local_fedipub_entities 스코프가
      # `where federated_url: nil`). 따라서 id 가 nil 이면 이 조회가 무관한 로컬
      # post 를 반환하고, Update 액티비티는 그 레코드를 assign_attributes + save! 로
      # 덮어쓴다(data_entity.rb). 로깅만으로는 막을 수 없는 자리다.
      if hash["id"].blank?
        logger.warn { "handle_federated_object?: rejecting object with no id (type=#{hash['type'].inspect} attributedTo=#{hash['attributedTo'].inspect})" }
        return false
      end

      in_reply_to = hash["inReplyTo"].to_s

      # inReplyTo가 없으면 원문 → 수락
      return true if in_reply_to.blank?

      # 로컬 답글은 실제 대상이 있을 때만 수락한다. 문자열 포함 여부만 검사하면
      # 없는 대상을 가리키는 답글이 부모 없는 최상위 포스트로 저장된다.
      if local_reply_target?(in_reply_to)
        return true if local_reply_target(in_reply_to)

        logger.warn { "handle_federated_object?: rejecting missing local inReplyTo #{in_reply_to.inspect}" }
        return false
      end

      # inReplyTo가 기존 post의 federated_url이면 수락
      Post.exists?(federated_url: in_reply_to)
    end
  end
end
