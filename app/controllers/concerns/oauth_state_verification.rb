# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# OAuth 콜백의 `state` 파라미터를 install 때 세션에 저장한 값과 비교해 CSRF를 막는다.
# 공격자가 자기 계정으로 받은 `code`를 피해자 브라우저의 콜백에 실어 보내도,
# 피해자 세션의 state와 맞지 않으므로 연동이 만들어지지 않는다.
#
# 토큰 교환(`exchange_code`)보다 먼저 호출해야 한다. 교환이 먼저 일어나면
# 검증에 실패해도 공격자의 `code`는 이미 소비된 뒤다.
module OauthStateVerification
  extend ActiveSupport::Concern

  private

  # 세션의 state는 한 번 꺼내면 지운다. 성공이든 실패든 같은 state를 재사용하지 못하게 한다.
  # 세션에 state가 없거나(install을 거치지 않은 콜백) 파라미터가 비어 있으면 거부한다.
  #: (Symbol session_key) -> bool
  def valid_oauth_state?(session_key)
    stored_state = session.delete(session_key).to_s
    incoming_state = params[:state].to_s
    return false if stored_state.empty? || incoming_state.empty?

    ActiveSupport::SecurityUtils.secure_compare(stored_state, incoming_state)
  end
end
