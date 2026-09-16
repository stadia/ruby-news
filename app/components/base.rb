# typed: true
# frozen_string_literal: true

class Components::Base < Phlex::HTML
  include RubyUI
  # Include any helpers you want to be available across all components
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::T

  private

  # 처리된 변형의 .url 은 public R2 서비스에서 직접 CDN URL을 주므로 리다이렉트
  # 왕복을 없앤다. 단 변형이 아직 처리되지 않았으면 .url 이 실제 파일이 없는 URL을
  # 반환해 브라우저가 404를 받으므로, 먼저 processed 로 존재를 보장한다 —
  # track_variants=true 라 이는 변형 레코드 DB 조회이고(R2 HEAD 아님), 잡이 미리
  # 처리해 뒀다면 조회만, 아니면 동기 변환+업로드 후 직접 URL을 얻는다.
  # public URL을 만들 수 없는 서비스(dev/test의 Disk는 url_options 필요)면 기본
  # 리다이렉트 라우트로 폴백한다 — 요청 컨텍스트에서 항상 동작하고 지연 처리된다.
  def cdn_variant_url(attachment, variant_name)
    variant = attachment.variant(variant_name)
    direct = begin
      variant.processed.url
    rescue StandardError => e
      # dev/test의 Disk 서비스는 url_options 미설정으로 예상된 실패라 조용히
      # 폴백한다. 그 외(프로덕션의 R2 인증 실패·변형 오류 등)는 사이트 전역 LCP
      # 회귀 신호이므로 삼키지 않고 로깅한다("no silent failures").
      unless Rails.env.local?
        Rails.logger.error("cdn_variant_url failed (#{variant_name}): #{e.class} - #{e.message}")
      end
      nil
    end
    direct.presence || helpers.url_for(variant)
  end

  def safe_url(url)
    uri = URI.parse(url.to_s)
    %w[http https].include?(uri.scheme) ? url : nil
  rescue URI::InvalidURIError
    nil
  end

  def post_permalink_path(post)
    if post.blog? && post.user
      user_profile_blog_post_path(username: post.user.username, slug: post)
    else
      post_path(post)
    end
  end

  if Rails.env.development?
    def before_template
      comment { "Before #{self.class.name}" }
      super
    end
  end
end
