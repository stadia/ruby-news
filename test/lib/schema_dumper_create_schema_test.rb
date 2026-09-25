# frozen_string_literal: true

require "test_helper"

# config/initializers/schema_dumper_create_schema.rb가 덤프의 create_schema에
# if_not_exists: true를 붙이고, Rails 덤프 형식이 바뀌면 조용히 넘어가지 않는지 고정.
class SchemaDumperCreateSchemaTest < ActiveSupport::TestCase
  test "덤프의 create_schema에 if_not_exists: true를 붙인다" do
    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)

    assert_includes stream.string, %(create_schema "ra_news", if_not_exists: true)
  end

  test "create_schema 덤프 형식이 바뀌어 옵션을 붙이지 못하면 예외를 낸다" do
    dumper = Class.new do
      def schemas(stream) = stream.puts(%(  create_schema("ra_news")))
      prepend IdempotentCreateSchemaDump
    end

    error = assert_raises(RuntimeError) { dumper.new.send(:schemas, StringIO.new) }
    assert_includes error.message, "create_schema"
  end
end
