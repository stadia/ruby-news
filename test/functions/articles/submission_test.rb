# frozen_string_literal: true

require "test_helper"

module Articles
  class SubmissionTest < ActiveSupport::TestCase
    test "분류할 수 없는 유니크 위반은 원래 예외를 전파한다" do
      article = new_article
      error = ActiveRecord::RecordNotUnique.new("unknown unique violation")

      article.stub(:save, -> { raise error }) do
        assert_same error, assert_raises(ActiveRecord::RecordNotUnique) {
          Submission.save_submitted(article, user_id: users(:john).id)
        }
      end
    end

    test "URL 인덱스 위반은 중복이며 제약 이름과 오류 상세를 error로 남긴다" do
      error = unique_violation(:url)
      article = new_article
      messages = []
      Rails.logger.stub(:error, ->(message) { messages << message }) do
        article.stub(:save, -> { raise error }) do
          assert_equal :duplicate, Submission.save_submitted(article, user_id: users(:john).id)
        end
      end

      assert messages.any? { |message| message.include?("index_articles_on_url") && message.include?("PG::UniqueViolation") }
    end

    test "slug 재시도도 충돌하면 한 번만 재시도하고 충돌로 돌려준다" do
      error = unique_violation(:slug)
      article = new_article
      saves = 0

      article.stub(:save, -> { saves += 1; raise error }) do
        assert_equal :duplicate, Submission.save_submitted(article, user_id: users(:john).id)
      end
      assert_equal 2, saves
    end

    test "slug 재시도 뒤 URL 충돌은 중복으로 처리한다" do
      errors = [ unique_violation(:slug), unique_violation(:url) ]
      article = new_article

      article.stub(:save, -> { raise errors.shift }) do
        assert_equal :duplicate, Submission.save_submitted(article, user_id: users(:john).id)
      end
    end

    test "slug 재시도 뒤 알 수 없는 위반은 전파한다" do
      error = ActiveRecord::RecordNotUnique.new("fedipub unique violation")
      errors = [ unique_violation(:slug), error ]
      article = new_article

      article.stub(:save, -> { raise errors.shift }) do
        assert_same error, assert_raises(ActiveRecord::RecordNotUnique) {
          Submission.save_submitted(article, user_id: users(:john).id)
        }
      end
    end

    test "호스트 표기가 다른 origin_url도 검증 전에 통일한다" do
      existing = articles(:similar_article)
      article = Article.new(url: existing.url.sub("example.com", "EXAMPLE.COM"), user: existing.user)

      assert_equal :duplicate, Submission.save_submitted(article, user_id: users(:john).id)
      assert_equal existing.origin_url, article.origin_url
      assert_equal existing, Submission.existing_for(article)
    end

    test "fedipub의 실제 유니크 위반은 기사 중복으로 숨기지 않는다" do
      first = Fedipub::Activity.create!(actor: users(:john).fedipub_actor, action: "Create", entity: articles(:ruby_article))
      second = Fedipub::Activity.create!(actor: users(:john).fedipub_actor, action: "Create", entity: articles(:similar_article))
      error = begin
        Article.transaction(requires_new: true) { second.update_columns(uuid: first.uuid) }

        flunk "fedipub UUID 인덱스 위반이 필요하다"
      rescue ActiveRecord::RecordNotUnique => violation
        violation
      end
      article = new_article

      article.stub(:save, -> { raise error }) do
        assert_same error, assert_raises(ActiveRecord::RecordNotUnique) {
          Submission.save_submitted(article, user_id: users(:john).id)
        }
      end
    end

    test "URL 오류만 안내로 바꾸고 사용자가 없는 오류는 보존한다" do
      article = new_article
      article.user = nil
      article.url = articles(:ruby_article).url
      article.origin_url = articles(:ruby_article).origin_url

      assert_equal :invalid, Submission.save_submitted(article, user_id: users(:john).id)
      assert article.errors.of_kind?(:user, :blank)
    end

    test "재시도 검증에서 준비된 URL이 중복되면 중복으로 돌려준다" do
      article = new_article
      original_save = article.method(:save)
      error = unique_violation(:slug)
      attempts = 0

      article.stub(:save, -> {
        attempts += 1
        if attempts == 1
          article.url = articles(:similar_article).url
          raise error
        end
        original_save.call
      }) do
        assert_equal :duplicate, Submission.save_submitted(article, user_id: users(:john).id)
      end
    end

    test "등록 오류 번역은 모든 지원 로케일에 실제로 존재한다" do
      expected = {
        ko: [ "삭제되었거나 등록 대상에서 제외된 글의 URL입니다.", "등록 중 충돌이 발생했습니다. 잠시 후 다시 시도해 주세요." ],
        en: [ "This URL belongs to an article that was deleted or filtered out.", "A conflict occurred while registering. Please try again shortly." ],
        ja: [ "削除またはフィルタリングされた記事のURLのため、再登録できません。", "登録中に競合が発生しました。しばらくしてから再度お試しください。" ]
      }
      expected.each do |locale, messages|
        %w[discarded_url submit_conflict].zip(messages).each do |key, message|
          assert_equal message, I18n.t(key, scope: "activerecord.errors.models.article.attributes.base", locale: locale, fallback: false, raise: true)
        end
        assert I18n.exists?("activerecord.errors.models.article.attributes.base.partial_duplicate", locale, fallback: false)
      end
    end

    test "충돌 로그는 사용자와 안전한 URL을 남기고 인증 정보와 쿼리를 숨긴다" do
      articles(:similar_article).update_columns(origin_url: "https://example.com/path)?token=secret")
      error = unique_violation(:origin_url)
      article = new_article
      article.url = "https://alice:password@example.com/signed?token=secret&line=%0Aforged"
      messages = []
      Rails.logger.stub(:error, ->(message) { messages << message }) do
        article.stub(:save, -> { raise error }) do
          Submission.save_submitted(article, user_id: users(:john).id)
        end
      end
      message = messages.join

      assert_includes message, "https://example.com/signed"
      assert_includes message, "user=#{users(:john).id}"
      assert_includes message, "Key (origin_url)=(FILTERED)"
      assert_not_includes message, "password"
      assert_not_includes message, "secret"
      assert_not_includes message, "forged"
    end

    private

    def new_article
      Article.new(url: "https://example.com/submission-test", origin_url: "https://example.com/submission-test", user: users(:john))
    end

    def unique_violation(column)
      Article.transaction(requires_new: true) do
        articles(:ruby_article).update_columns(column => articles(:similar_article).public_send(column))
      end

      flunk "실제 PostgreSQL 유니크 위반이 필요하다"
    rescue ActiveRecord::RecordNotUnique => error
      error
    end
  end
end
