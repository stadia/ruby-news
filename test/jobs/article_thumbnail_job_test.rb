# frozen_string_literal: true

require "test_helper"

class ArticleThumbnailJobTest < ActiveSupport::TestCase
  # 1x1 투명 PNG (변형 실제 처리는 스텁하므로 attached? 만 참이면 된다)
  ONE_PX_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
  )

  # ruby_llm 2.0은 생성된 이미지를 content가 아니라 Message#attachments에 담는다.
  # 첨부는 Gemini 프로토콜이 inlineData를 디코딩할 때와 같은 방식으로 만든다.
  test "AI 썸네일은 에이전트 응답 메시지의 이미지 첨부를 붙인다" do
    article = articles(:ruby_article)
    article.update!(summary_key: [ "요점" ])
    image = RubyLLM::Attachment.new(StringIO.new(ONE_PX_PNG), filename: "image_0.png")
    response = RubyLLM::Message.new(role: :assistant, content: nil, attachments: [ image ])
    agent = Object.new
    agent.define_singleton_method(:ask) { |_prompt| response }

    ArticleImageAgent.stub(:new, agent) do
      ArticleThumbnailJob.new.send(:generate_ai_thumbnail, article)
    end

    assert_predicate article.thumbnail, :attached?
    assert_equal "image/png", article.thumbnail.content_type
  end

  test "썸네일이 이미 있으면 재생성 없이 변형만 다시 처리한다" do
    article = articles(:ruby_article)
    article.thumbnail.attach(io: StringIO.new(ONE_PX_PNG), filename: "t.png", content_type: "image/png")

    job = ArticleThumbnailJob.new
    processed = false
    job.stub(:process_thumbnail_variants, ->(_article) { processed = true }) do
      job.stub(:generate_ai_thumbnail, ->(_article) { flunk "should not regenerate thumbnail" }) do
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
