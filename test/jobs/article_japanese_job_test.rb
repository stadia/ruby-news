# frozen_string_literal: true

require "test_helper"

class ArticleJapaneseJobTest < ActiveSupport::TestCase
  test "기사를 ArticleJapaneseService로 번역한다" do
    article = articles(:ruby_article)
    translated = nil
    service = Object.new
    service.define_singleton_method(:call) do |a|
      translated = a
      Dry::Monads::Success(a)
    end

    ArticleJapaneseService.stub(:new, -> { service }) do
      ArticleJapaneseJob.perform_now(article.id)
    end

    assert_equal article, translated
  end

  test "폐기된 기사는 번역하지 않는다" do
    article = articles(:ruby_article)
    article.discard!

    ArticleJapaneseService.stub(:new, -> { flunk "폐기된 기사에 번역 서비스가 호출됐다" }) do
      ArticleJapaneseJob.perform_now(article.id)
    end
  end
end
