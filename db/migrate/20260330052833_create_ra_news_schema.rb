# frozen_string_literal: true

# database.yml 의 schema_search_path 첫 항목인 ra_news 스키마를 생성한다.
#
# PostgreSQL 은 search_path 에 없는 스키마를 조용히 건너뛰고 다음 항목(public)에
# 객체를 만든다. 지금까지 ra_news 를 만드는 코드는 gitignore 대상인 db/schema.rb
# 의 create_schema 뿐이어서, 신규 클론에서 db:migrate 로 셋업하면 모든 테이블이
# public 에 생성됐다(프로덕션은 ra_news).
#
# 최초 스키마(20260330052834_init_schema)보다 앞선 타임스탬프를 갖는다. 이미
# 적용된 환경에서는 IF NOT EXISTS 로 무해하게 통과한다.
class CreateRaNewsSchema < ActiveRecord::Migration[8.1]
  SCHEMA_NAME = "ra_news"

  def up
    return unless search_path_includes_schema?

    execute("CREATE SCHEMA IF NOT EXISTS #{quote_schema}")
  end

  def down
    # 스키마를 지우면 그 안의 테이블이 전부 함께 사라진다. init_schema 롤백보다
    # 파괴적이므로 되돌리지 않는다.
  end

  private

  # sqlite 등 다른 어댑터나 search_path 를 쓰지 않는 환경에서는 아무것도 하지 않는다.
  def search_path_includes_schema?
    return false unless connection.adapter_name.match?(/postg/i)

    connection.schema_search_path.to_s.split(",").map { it.strip.delete('"') }.include?(SCHEMA_NAME)
  end

  def quote_schema
    connection.quote_table_name(SCHEMA_NAME)
  end
end
