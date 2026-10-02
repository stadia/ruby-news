# frozen_string_literal: true

require "test_helper"

class Madmin::ArticlesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "기사 목록은 전문 검색 결과에 필터 조건을 함께 적용한다" do
    sign_in_as users(:admin)
    articles(:site_only_article).update_pg_search_document
    # schema.rb는 검색 트리거를 덤프하지 않으므로 테스트용 검색 벡터를 준비한다.
    PgSearch::Document.where(searchable_type: "Article")
                      .update_all("tsvector_content_tsearch = to_tsvector('korean', content)")

    get madmin_articles_path(q: "Ruby", scope: "kept", filters: [ { column: "is_related", operator: "false" } ])

    assert_response :success
    assert_select "#filters[popover]"
    assert_select "tbody a[href=?]", madmin_article_path(articles(:site_only_article))
    assert_select "tbody a[href=?]", madmin_article_path(articles(:ruby_article)), count: 0
  end

  test "기사 목록은 검색어 없이도 스코프와 필터 조건을 함께 적용한다" do
    sign_in_as users(:admin)

    get madmin_articles_path(scope: "discarded", filters: [ { column: "is_related", operator: "false" } ])

    assert_response :success
    assert_select "tbody tr", count: 2
    assert_select "tbody a[href=?]", madmin_article_path(articles(:deleted_article))
    assert_select "tbody a[href=?]", madmin_article_path(articles(:site_only_article)), count: 0
  end

  test "기사 수정은 Lexxy 본문과 봇 작성자를 유지한다" do
    sign_in_as users(:admin)
    article = articles(:ruby_article)

    patch madmin_article_path(article), params: { article: { body: "업데이트된 기사 본문" } }

    assert_redirected_to madmin_article_path(article)
    assert_equal "업데이트된 기사 본문", article.reload.body
    assert_equal User.first_bot.id, article.user_id
  end

  test "일본어 재번역은 번역 잡을 큐에 넣는다" do
    sign_in_as users(:admin)
    article = articles(:ruby_article)

    assert_enqueued_with(job: ArticleJapaneseJob, args: [ article.id ]) do
      put translate_japanese_madmin_article_path(article)
    end

    assert_redirected_to madmin_article_path(article)
  end

  test "폐기된 기사는 일본어 재번역을 거부한다" do
    sign_in_as users(:admin)
    article = articles(:ruby_article)
    article.discard!

    assert_no_enqueued_jobs(only: ArticleJapaneseJob) do
      put translate_japanese_madmin_article_path(article)
    end

    assert_redirected_to madmin_article_path(article)
  end
end
