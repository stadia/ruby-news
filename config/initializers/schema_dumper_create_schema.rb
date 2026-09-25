# typed: false
# frozen_string_literal: true
# rbs_inline: enabled

# db/schema.rb의 `create_schema "ra_news"`를 `if_not_exists: true`로 덤프한다.
#
# Rails의 PostgreSQL 덤퍼는 옵션 없이 `create_schema`를 쓴다. 테이블은
# `force: :cascade`로 덮어쓰는데 스키마만 그렇지 않아서, ra_news가 이미 있는 DB
# (마이그레이션으로 셋업한 로컬 DB 등)에 `db:schema:load`를 하면
# `PG::DuplicateSchema`로 첫 줄에서 죽는다. `create_schema`는 이미
# `if_not_exists:`를 받으므로 덤프 결과에만 옵션을 붙인다.
#
# Rails가 덤프 형식을 바꿔 정규식이 맞지 않으면 원래 출력을 그대로 쓴다.
# 그 경우 schema.rb diff에서 `if_not_exists: true`가 빠지는 것으로 드러난다.
module IdempotentCreateSchemaDump
  private

  def schemas(stream)
    buffer = StringIO.new
    super(buffer)
    stream.print buffer.string.gsub(/^(  create_schema "[^"]+")$/, '\1, if_not_exists: true')
  end
end

ActiveSupport.on_load(:active_record_postgresqladapter) do
  dumper = ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper
  dumper.prepend(IdempotentCreateSchemaDump) unless dumper < IdempotentCreateSchemaDump
end
