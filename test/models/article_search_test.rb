# frozen_string_literal: true

require "test_helper"

class ArticleSearchTest < ActiveSupport::TestCase
  setup do
    PgSearch::Document.delete_all
    @both = articles(:ruby_article)
    @browser_only = articles(:similar_article)
    @interaction_only = articles(:site_only_article)
    @english = articles(:youtube_ruby_talk)
    @korean = articles(:korean_content_article)

    index_article(@both, "rails-jsdom: ブラウザなしでインタラクションをテストする Ruby")
    index_article(@browser_only, "ブラウザでページを表示する")
    index_article(@interaction_only, "インタラクションの設計")
    index_article(@english, "Ruby performance and Rails testing")
    index_article(@korean, "레일스 성능 개선과 테스트")
  end

  test "일본어 복수 검색어는 ASCII 공백으로 나누어 모두 일치해야 한다" do
    assert_equal [ @both.id ], Article.full_text_search_for("ブラウザ インタラクション").pluck(:id)
  end

  test "일본어 복수 검색어는 전각 공백으로 나누어 모두 일치해야 한다" do
    assert_equal [ @both.id ], Article.full_text_search_for("ブラウザ　インタラクション").pluck(:id)
  end

  test "일본어 검색어의 앞뒤와 반복 공백 및 단어 순서를 정규화한다" do
    assert_equal [ @both.id ], Article.full_text_search_for("　インタラクション \t ブラウザ　ブラウザ　").pluck(:id)
  end

  test "한 단어만 있는 문서는 일본어 AND 검색에 포함하지 않는다" do
    assert_empty Article.full_text_search_for("ブラウザ インタラクション データベース")
  end

  test "혼합 검색은 tsearch가 가나를 버려도 모든 검색어를 요구한다" do
    assert_equal [ @both.id ], Article.full_text_search_for("Ruby ブラウザ").pluck(:id)
    assert_empty Article.full_text_search_for("performance ブラウザ")
  end

  test "일본어 단일 검색어의 부분 일치를 유지한다" do
    assert_equal [ @both.id, @browser_only.id ].sort, Article.full_text_search_for("ブラウザ").pluck(:id).sort
  end

  test "영어 검색은 대소문자와 기존 websearch OR 문법을 유지한다" do
    assert_equal [ @english.id ], Article.full_text_search_for("RUBY performance").pluck(:id)
    assert_equal [ @both.id, @english.id ].sort, Article.full_text_search_for("Ruby OR performance").pluck(:id).sort
    assert_not_includes Article.full_text_search_for("Ruby").to_sql, "LIKE"
  end

  test "한국어 검색은 형태소 기반 다중 검색과 tsearch 전용 경로를 유지한다" do
    assert_equal [ @korean.id ], Article.full_text_search_for("성능 테스트").pluck(:id)
    assert_empty Article.full_text_search_for("성능 데이터베이스")
    assert_not_includes Article.full_text_search_for("성능 테스트").to_sql, "LIKE"
  end

  test "빈 검색어는 결과를 반환하지 않는다" do
    [ nil, "", " \t　 " ].each do |query|
      assert_empty Article.full_text_search_for(query)
    end
  end

  test "일본어 LIKE 검색은 와일드카드를 문자 그대로 처리한다" do
    [ "ブラウザ%", "ブラウザ_", "ブラウザ\\" ].each do |query|
      index_article(@browser_only, "#{query} インタラクション")

      assert_equal [ @browser_only.id ], Article.full_text_search_for("#{query} インタラクション").pluck(:id)
    end
  end

  test "SQL 구문이 섞인 검색어는 결과 범위를 넓히지 않는다" do
    assert_empty Article.full_text_search_for("ブラウザ '); SELECT 1; --")
  end

  test "일본어 검색은 중복 제거 전 입력 토큰 열 개까지 허용한다" do
    words = %w[ブラウザ インタラクション テスト コード データ サーバー クライアント メモリ キャッシュ パフォーマンス]
    index_article(@both, words.reverse.join("・"))

    assert_equal [ @both.id ], Article.full_text_search_for("　#{words.join(" ")}　").pluck(:id)
    assert_equal [ @both.id, @browser_only.id ].sort, Article.full_text_search_for(([ "ブラウザ" ] * 10).join(" ")).pluck(:id).sort
    assert_empty Article.full_text_search_for((words + [ "ブラウザ" ]).join(" "))
    assert_empty Article.full_text_search_for((words + [ "ネットワーク" ]).join(" "))
  end

  private

  def index_article(article, content)
    document = PgSearch::Document.find_or_initialize_by(searchable: article)
    document.update!(content: content)
    # schema.rb를 로드한 테스트 DB에는 운영의 tsvector 갱신 트리거가 없으므로 같은 사전으로 채운다.
    PgSearch::Document.where(id: document.id).update_all("tsvector_content_tsearch = to_tsvector('korean', content)")
  end
end
