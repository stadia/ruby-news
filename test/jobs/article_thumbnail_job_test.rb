# frozen_string_literal: true

require "test_helper"

class ArticleThumbnailJobTest < ActiveSupport::TestCase
  # 1x1 투명 PNG (변형 실제 처리는 스텁하므로 attached? 만 참이면 된다)
  ONE_PX_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
  )

  test "YouTube가 아닌 기사는 Articles::Thumbnail로 AI 썸네일을 생성한다" do
    article = articles(:ruby_article)
    generated = nil

    Articles::Thumbnail.stub(:generate, ->(a) { generated = a }) do
      ArticleThumbnailJob.perform_now(article.id)
    end

    assert_equal article, generated
  end

  test "썸네일이 이미 있으면 재생성 없이 변형만 다시 처리한다" do
    article = articles(:ruby_article)
    article.thumbnail.attach(io: StringIO.new(ONE_PX_PNG), filename: "t.png", content_type: "image/png")

    job = ArticleThumbnailJob.new
    processed = false
    job.stub(:process_thumbnail_variants, ->(_article) { processed = true }) do
      Articles::Thumbnail.stub(:generate, ->(_article) { flunk "should not regenerate thumbnail" }) do
        job.stub(:attach_youtube_thumbnail, ->(_article) { flunk "should not regenerate thumbnail" }) do
          job.perform(article.id)
        end
      end
    end

    assert processed, "already-attached 분기에서 변형을 다시 처리해야 한다"
  end

  test "process_thumbnail_variants는 변형 처리 에러를 삼키지 않고 전파한다" do
    article = articles(:ruby_article)

    failing_variant = Object.new
    failing_variant.define_singleton_method(:processed) { raise "boom" }
    fake_attachment = Object.new
    fake_attachment.define_singleton_method(:variant) { |_name| failing_variant }

    job = ArticleThumbnailJob.new

    article.stub(:thumbnail, fake_attachment) do
      assert_raises(RuntimeError) { job.send(:process_thumbnail_variants, article) }
    end
  end
end
