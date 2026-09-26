# typed: false
# frozen_string_literal: true
# rbs_inline: enabled

# 인바운드 ActivityPub 답글은 inReplyTo 호스트를 routing host와 비교해 로컬
# 대상인지 가린다(Posts::FederationIngest.local_reply_target?). 이 값이 비면
# 로컬 답글이 전부 원격으로 분류되어 조용히 사라지므로, 요청마다 검사하지
# 않고 부팅 시점에 한 번 막는다.
Rails.application.config.after_initialize do
  if Rails.application.routes.default_url_options[:host].blank?
    raise "Rails.application.routes.default_url_options[:host] must be set (config/environments/#{Rails.env}.rb)"
  end
end
