# frozen_string_literal: true

# oauth_accounts_provider_allowed 제약의 식을 schema.rb 왕복에 안정적인 형태로 다시 건다.
# 허용 값(google_oauth2, apple, github)은 바뀌지 않는다.
#
# 기존 식 `provider IN (...)`은 PostgreSQL이 varchar 캐스트가 섞인
# `= ANY (ARRAY['x'::character varying, ...]::text[])`로 저장한다. 이 덤프를
# 다시 로드하면 `'x'::character varying::text`로 또 한 번 정규화되어, 마이그레이션으로
# 만든 DB와 schema.rb로 만든 DB의 덤프가 서로 달라진다. schema.rb를 커밋하면
# 셋업 경로에 따라 diff가 계속 흔들리므로, 처음부터 text 배열로 써서
# 어느 경로든 같은 식이 저장되게 한다.
class NormalizeOauthAccountsProviderCheck < ActiveRecord::Migration[8.1]
  NAME = "oauth_accounts_provider_allowed"

  def up
    remove_check_constraint :oauth_accounts, name: NAME
    add_check_constraint :oauth_accounts,
      "provider::text = ANY (ARRAY['google_oauth2'::text, 'apple'::text, 'github'::text])",
      name: NAME
  end

  def down
    remove_check_constraint :oauth_accounts, name: NAME
    add_check_constraint :oauth_accounts, "provider IN ('google_oauth2', 'apple', 'github')", name: NAME
  end
end
