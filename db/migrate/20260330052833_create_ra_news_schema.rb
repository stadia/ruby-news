# frozen_string_literal: true

# database.yml 의 schema_search_path 첫 항목인 ra_news 스키마를 생성한다.
#
# PostgreSQL 은 search_path 에 있지만 실제로 존재하지 않는 스키마를 건너뛰고
# 다음 항목(public)에 객체를 만든다. 이 마이그레이션 이전에는 ra_news 를 만드는
# 코드가 (당시 gitignore 대상이던) db/schema.rb 의 create_schema 뿐이어서, 신규
# 클론에서 db:migrate 로 셋업하면 모든 테이블이 public 에 생성됐다(프로덕션은 ra_news).
#
# 최초 스키마(20260330052834_init_schema)보다 앞선 타임스탬프를 갖는다.
# - ra_news 가 이미 있는 환경(프로덕션 등): 아무것도 하지 않는다.
# - 앱 테이블이 public 에 셋업된 기존 환경: 여기서 ra_news 를 만들면 이후 테이블만
#   ra_news 에 생겨 두 스키마로 갈라지므로, 멈추고 DB 재생성을 안내한다.
class CreateRaNewsSchema < ActiveRecord::Migration[8.1]
  SCHEMA_NAME = "ra_news"

  def up
    return unless postgresql?

    unless search_path_includes_schema?
      say "WARNING: schema_search_path(#{connection.schema_search_path})에 #{SCHEMA_NAME}가 없어 " \
          "스키마를 만들지 않는다. 앱 테이블이 #{SCHEMA_NAME}가 아닌 곳에 생긴다."
      return
    end
    # 스키마가 이미 있으면 CREATE SCHEMA 를 내지 않는다. IF NOT EXISTS 여도 DB 의
    # CREATE 권한 검사는 거치므로, 그 권한이 없는 롤에서 배포가 막히지 않게 한다.
    return if connection.schema_exists?(SCHEMA_NAME)

    raise_if_set_up_in_public
    execute("CREATE SCHEMA #{quote_schema}")
  end

  def down
    # init_schema 가 이미 되돌릴 수 없으므로(IrreversibleMigration) 스키마를 DROP 할
    # 이유가 없다. 다시 up 해도 스키마가 있으면 그냥 통과한다.
    say "#{SCHEMA_NAME} 스키마는 의도적으로 유지한다"
  end

  private

  def postgresql?
    connection.adapter_name.match?(/postg/i)
  end

  def search_path_includes_schema?
    connection.schema_search_path.to_s.split(",").map { it.strip.delete('"') }.include?(SCHEMA_NAME)
  end

  def raise_if_set_up_in_public
    return unless connection.select_value("SELECT to_regclass('public.articles')")

    raise <<~MSG
      앱 테이블이 public 스키마에 셋업된 DB다(#933). 여기서 #{SCHEMA_NAME} 스키마를 만들면
      이후 테이블만 #{SCHEMA_NAME}에 생겨 두 스키마로 갈라진다.
      DB를 다시 만들거나(bin/rails db:drop db:create db:migrate — test DB도 함께 지워진다),
      데이터를 보존해야 하면 CREATE SCHEMA #{SCHEMA_NAME} 후 ALTER TABLE ... SET SCHEMA #{SCHEMA_NAME}로 옮겨라.
    MSG
  end

  def quote_schema
    connection.quote_table_name(SCHEMA_NAME)
  end
end
