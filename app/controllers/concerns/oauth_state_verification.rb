# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# OAuth 콜백의 `state`를 install 때 세션에 저장한 값과 비교한다.
# install을 시작한 같은 브라우저 세션에서 돌아온 콜백만 받는다.
#
# 토큰 교환(`exchange_code`)보다 먼저 검증해 거부할 콜백에서 토큰 발급이나
# webhook 생성 같은 외부 API의 부수효과가 발생하지 않게 한다.
module OauthStateVerification
  extend ActiveSupport::Concern

  private

  # 세션의 state는 한 번 꺼내면 지운다. 성공이든 실패든 같은 state를 재사용하지 못하게 한다.
  # install을 거치지 않았거나 세션이 유실된 경우, 또는 파라미터가 비어 있으면 거부한다.
  #: (Symbol session_key) -> bool
  def valid_oauth_state?(session_key)
    stored_state = session.delete(session_key).to_s
    incoming_state = params[:state].to_s
    return reject_oauth_state(:missing_session_state, session_key) if stored_state.empty?
    return reject_oauth_state(:missing_param_state, session_key) if incoming_state.empty?
    return reject_oauth_state(:mismatch, session_key) unless ActiveSupport::SecurityUtils.secure_compare(stored_state, incoming_state)

    true
  end

  #: (Symbol reason, Symbol session_key) -> bool
  def reject_oauth_state(reason, session_key)
    logger.warn("OAuth state rejected reason=#{reason} session_key=#{session_key} host=#{request.host}")
    false
  end
end
