# frozen_string_literal: true

require "test_helper"

class ArticleBatchJobTest < ActiveSupport::TestCase
  test "배치 처리 후 전체 multisearch 재빌드를 호출하지 않는다" do
    article = articles(:site_only_article)
    created_at = 1.day.from_now
    article.update_columns(title_ko: nil, created_at:)

    called_articles = []
    fake_service = Object.new
    fake_service.define_singleton_method(:call) do |record|
      called_articles << record
      record.update!(title_ko: "배치 요약 결과", summary_key: [ "요약" ])
      Struct.new(:success?).new(true)
    end

    PgSearch::Multisearch.stub(:rebuild, ->(*, **_) { raise "should not be called" }) do
      ArticleAgentsService.stub(:new, -> { fake_service }) do
        job = ArticleBatchJob.new
        job.stub(:check_rate_limit, true) do
          job.stub(:sleep, nil) do
            job.perform(1.hour.from_now)
          end
        end
      end
    end

    assert_equal [ article ], called_articles
  end

  # 실패한 기사가 매 실행 맨 앞에 잡혀 한도를 차지하지 않도록 뒤로 보낸다(#1060).
  test "실패한 기사는 뒤로 보내 다음 실행에서 다른 기사를 처리한다" do
    failing = articles(:site_only_article)
    other = articles(:ruby_article)
    failing.update_columns(title_ko: nil, created_at: 1.day.from_now, updated_at: 2.years.ago)
    other.update_columns(title_ko: nil, created_at: 1.day.from_now, updated_at: 1.year.ago)

    called_ids = []
    fake_service = Object.new
    fake_service.define_singleton_method(:call) do |record|
      called_ids << record.id
      raise "LLM 4xx" if record.id == failing.id
    end

    ArticleAgentsService.stub(:new, -> { fake_service }) do
      2.times do
        job = ArticleBatchJob.new
        allowed = [ true, false ]
        job.stub(:check_rate_limit, -> { allowed.shift }) do
          job.stub(:sleep, nil) { job.perform(1.hour.from_now) }
        end
      end
    end

    assert_equal [ failing.id, other.id ], called_ids
  end

  # 자정 직전 수집 기사가 당일 처리되지 못해도 다음 날 실행에서 처리돼야 한다(#1060).
  test "기본 조회 범위는 전날 수집한 기사도 포함한다" do
    article = articles(:site_only_article)
    article.update_columns(title_ko: nil, created_at: Time.zone.now.beginning_of_day - 1.minute, updated_at: 10.years.ago)

    called_ids = []
    fake_service = Object.new
    fake_service.define_singleton_method(:call) { |record| called_ids << record.id }

    ArticleAgentsService.stub(:new, -> { fake_service }) do
      job = ArticleBatchJob.new
      allowed = [ true, false ]
      job.stub(:check_rate_limit, -> { allowed.shift }) do
        job.stub(:sleep, nil) { job.perform }
      end
    end

    assert_equal [ article.id ], called_ids
  end

  # 5분 주기 실행이 직전 실행의 카운터 만료 직전에 걸려 건너뛰지 않도록 한도 창은 주기보다 짧아야 한다(#1060).
  test "한도 창은 실행 주기(5분)보다 짧다" do
    assert_operator ArticleBatchJob.new.send(:rate_limit_window), :<, 5.minutes
  end
end
