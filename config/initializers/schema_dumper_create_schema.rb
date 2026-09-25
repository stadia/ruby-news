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
# Rails가 덤프 형식을 바꾸거나 private `schemas`를 없애면 패치가 조용히 빠진
# 덤프가 나오고, 문제는 나중에 `db:schema:load`에서야 드러난다. 그래서 둘 다
# 덤프 시점(개발·CI)에 예외로 알린다.
module IdempotentCreateSchemaDump
  private

  def schemas(stream)
    buffer = StringIO.new
    super(buffer)
    original = buffer.string
    patched = original.gsub(/^(  create_schema "[^"]+")$/, '\1, if_not_exists: true')
    if original.include?("create_schema") && !patched.include?("if_not_exists: true")
      raise "IdempotentCreateSchemaDump: create_schema 덤프 형식이 바뀌어 패치를 적용하지 못했다. " \
            "config/initializers/schema_dumper_create_schema.rb를 갱신하라:\n#{original}"
    end

    stream.print patched
  end
end

ActiveSupport.on_load(:active_record_postgresqladapter) do
  dumper = ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper
  unless dumper.private_method_defined?(:schemas)
    raise "IdempotentCreateSchemaDump: #{dumper}#schemas가 없다(Rails #{Rails.version}). " \
          "config/initializers/schema_dumper_create_schema.rb를 갱신하라"
  end
  dumper.prepend(IdempotentCreateSchemaDump) unless dumper < IdempotentCreateSchemaDump
end
