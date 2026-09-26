# typed: false
# frozen_string_literal: true
# rbs_inline: enabled

# 인바운드 ActivityPub 답글은 inReplyTo 호스트를 Hosts 목록과 routing host로
# 비교해 로컬 대상인지 가린다(Posts::FederationIngest.local_reply_target?).
# routing host가 비면 Hosts에 없는 호스트로 서비스하는 환경(test·dev 등)의
# 로컬 답글이 원격으로 분류되어 조용히 사라지므로, 요청마다 검사하지 않고
# 부팅 시점에 한 번 막는다.
Rails.application.config.after_initialize do
  if Rails.application.routes.default_url_options[:host].blank?
    raise "Rails.application.routes.default_url_options[:host] must be set (config/environments/#{Rails.env}.rb)"
  end
end
