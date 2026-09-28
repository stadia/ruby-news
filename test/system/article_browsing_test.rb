# frozen_string_literal: true

require "application_system_test_case"

class ArticleBrowsingTest < ApplicationSystemTestCase
  RECENT_ARTICLE_COUNT = 10

  # articles#index("지난 글")는 홈에 먼저 나오는 최근 관련 기사(24시간 안의 글, 9개가 안 되면
  # 최근 9개)를 뺀다(Articles::Query.excluded_related_article_ids). 픽스처의 관련 기사는 그보다
  # 적어 전부 빠지므로, 대상 기사를 오래된 글로 두고 그보다 최근인 관련 기사를 따로 만든다.
  setup do
    @article = articles(:ruby_article)
    @article.update_columns(created_at: 3.days.ago)

    now = Time.current
    Article.insert_all!(Array.new(RECENT_ARTICLE_COUNT) do |i|
      url = "https://recent.example/articles/#{i}"
      { title: "최근 글 #{i}", title_ko: "최근 기사 #{i}", url:, origin_url: url, host: "recent.example",
        slug: "recent-article-#{i}", published_at: now - i.minutes, is_related: true,
        user_id: @article.user_id, created_at: now - i.minutes, updated_at: now }
    end)
  end

  # articles#index/#show 는 authenticate_user! 를 skip 하므로 비로그인으로도 성립하는
  # 순수 조회 스모크. 목록에서 기사 카드를 클릭해 상세로 이동, 제목/본문 노출을 확인한다.
  test "비로그인 사용자가 목록에서 기사를 열어 상세를 조회한다" do
    visit articles_path

    # 기사 카드는 link_to article.display_title, article_path(article) 로 렌더된다.
    assert_text @article.display_title
    assert_no_text "최근 기사 0"
    click_link @article.display_title, match: :first

    # 상세 페이지: h1 에 display_title, 본문 영역에 display_summary_detail 의
    # introduction 이 노출되고 댓글 폼 제목이 보인다. (show 뷰는 article.body 가
    # 아니라 display_summary_detail/display_summary_body 를 렌더링한다.)
    assert_current_path article_path(@article)
    assert_text @article.display_title
    assert_text @article.display_summary_detail["introduction"]
    assert_text I18n.t("comments.comment_form.title")
  end
end
