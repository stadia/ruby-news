# frozen_string_literal: true

require "test_helper"

class Articles::SummaryPromptTest < ActiveSupport::TestCase
  test "일반 기사는 content 구분선 아래에 본문을 넣는다" do
    article = articles(:ruby_article)
    article.body = "본문 내용"

    prompt = Articles::SummaryPrompt.build(article)

    assert_includes prompt, "다음 기술 아티클을 분석하여"
    assert_includes prompt, "article_id: #{article.id}"
    assert_includes prompt, "--- content ---\n본문 내용"
    assert_not_includes prompt, "transcript"
  end

  test "YouTube 기사는 transcript 구분선과 자막 정리 지침을 쓴다" do
    article = articles(:youtube_ruby_talk)
    article.body = "자막 내용"

    prompt = Articles::SummaryPrompt.build(article)

    assert_includes prompt, "YouTube 영상의 자막을 분석하여"
    assert_includes prompt, "필러 단어"
    assert_includes prompt, "--- transcript ---\n자막 내용"
  end
end
