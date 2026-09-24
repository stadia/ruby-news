# frozen_string_literal: true

require "test_helper"

class Madmin::ArticlesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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
