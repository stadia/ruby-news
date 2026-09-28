# frozen_string_literal: true

# rbs_inline: enabled

require "test_helper"

class MastodonServiceTest < ActiveSupport::TestCase
  # Mastodon 클라이언트 응답을 시뮬레이션하는 Mock 객체
  MockResponse = Struct.new(:status, :body)

  setup do
    @article = articles(:ruby_article)
    @article.update(mastodon_id: nil) # 테스트 시작 시 mastodon_id 초기화
  end

  # === 포스팅 테스트 ===

  test "post_to_platform은 성공 시 mastodon_id를 저장한다" do
    mock_client = Minitest::Mock.new
    mock_response = MockResponse.new(200, { "id" => "123456789" })
    mock_client.expect(:post, mock_response, [ String ])

    service = MastodonService.new
    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :post)

      assert_predicate result, :success?
      assert_equal "123456789", result.value!
      assert_equal "123456789", @article.reload.mastodon_id
    end

    mock_client.verify
  end

  test "post_to_platform은 이미 포스팅된 경우 Failure를 반환한다" do
    @article.update(mastodon_id: "existing_id")

    mock_client = Minitest::Mock.new

    service = MastodonService.new
    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :post)

      assert_predicate result, :failure?
      assert_equal :already_posted, result.failure
    end
  end

  test "post_to_platform은 API 오류 시 Failure를 반환한다" do
    mock_client = Minitest::Mock.new
    mock_response = MockResponse.new(500, {})
    mock_client.expect(:post, mock_response, [ String ])

    service = MastodonService.new
    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :post)

      assert_predicate result, :failure?
      assert_equal 500, result.failure
    end

    mock_client.verify
  end

  test "post_to_platform은 is_related가 false인 경우 건너뛴다" do
    @article.update(is_related: false)

    service = MastodonService.new
    result = service.call(@article, command: :post)

    assert_predicate result, :failure?
    assert_equal :not_suitable, result.failure
  end

  test "post_to_platform은 slug가 없는 경우 건너뛴다" do
    @article.update(slug: nil)

    service = MastodonService.new
    result = service.call(@article, command: :post)

    assert_predicate result, :failure?
    assert_equal :not_suitable, result.failure
  end

  test "post_to_platform은 title_ko가 없는 경우 건너뛴다" do
    @article.update(title_ko: nil)

    service = MastodonService.new
    result = service.call(@article, command: :post)

    assert_predicate result, :failure?
    assert_equal :not_suitable, result.failure
  end

  # === 삭제 테스트 ===

  test "delete_from_platform은 성공 시 mastodon_id를 nil로 설정한다" do
    @article.update(mastodon_id: "123456789")

    mock_client = Minitest::Mock.new
    mock_response = MockResponse.new(200, {})
    mock_client.expect(:delete, mock_response, [ "123456789" ])

    service = MastodonService.new
    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :delete)

      assert_predicate result, :success?
      assert_nil @article.reload.mastodon_id
    end

    mock_client.verify
  end

  test "delete_from_platform은 mastodon_id가 없는 경우 Failure를 반환한다" do
    @article.update(mastodon_id: nil)

    service = MastodonService.new
    result = service.call(@article, command: :delete)

    assert_predicate result, :failure?
    assert_equal :no_social_id, result.failure
  end

  test "delete_from_platform은 API 오류 시 Failure를 반환한다" do
    @article.update(mastodon_id: "123456789")

    mock_client = Minitest::Mock.new
    mock_response = MockResponse.new(404, {})
    mock_client.expect(:delete, mock_response, [ "123456789" ])

    service = MastodonService.new
    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :delete)

      assert_predicate result, :failure?
      assert_equal 404, result.failure
    end

    mock_client.verify
  end

  # === 텍스트 생성 테스트 ===

  test "build_post_text는 올바른 형식의 텍스트를 생성한다" do
    service = MastodonService.new
    post_text = service.send(:build_post_text, @article)

    # 제목과 요약이 포함되어야 함
    assert_includes post_text, @article.title_ko

    # 링크가 포함되어야 함
    assert_includes post_text, "https://ruby-news.dev/articles/#{@article.slug}"
  end

  test "build_post_text는 태그를 포함한다" do
    # confirmed 태그 추가
    tag = tags(:ruby_tag)
    @article.tags << tag unless @article.tags.include?(tag)

    service = MastodonService.new
    post_text = service.send(:build_post_text, @article)

    # 태그 형식 확인 (#태그명)
    assert_match(/#\w+/, post_text)
  end

  test "build_post_text는 500자 이내로 제한한다" do
    # 긴 내용으로 테스트
    @article.update(
      title_ko: "A" * 95,
      summary_key: [ "B" * 300 ]
    )

    service = MastodonService.new
    post_text = service.send(:build_post_text, @article)

    assert_operator post_text.length, :<=, 500, "포스트 텍스트가 500자를 초과함: #{post_text.length}자"
  end

  # === 기타 테스트 ===

  test "알 수 없는 command는 ArgumentError를 발생시킨다" do
    service = MastodonService.new

    assert_raises(ArgumentError) do
      service.call(@article, command: :unknown)
    end
  end

  test "platform_name은 Mastodon을 반환한다" do
    service = MastodonService.new

    assert_equal "Mastodon", service.send(:platform_name)
  end

  test "platform_client는 Preference 설정을 조회해 전달한다" do
    config = Preference.create!(name: "mastodon_oauth", value: {
      "site" => "https://social.example", "client_id" => "test-id", "client_secret" => "test-secret",
      "access_token" => "test-access-token", "refresh_token" => "test-refresh-token",
      "expires_at" => 1.hour.from_now.to_i
    })
    Preference.stub(:get_object, ->(key) { assert_equal "mastodon_oauth", key; config }) do
      config.stub(:update, ->(*) { flunk "만료되지 않은 토큰은 저장하지 않아야 합니다" }) do
        client = MastodonService.new.send(:platform_client)

        assert_equal "Bearer test-access-token", client.client.headers["Authorization"]
      end
    end

    assert_equal "test-access-token", config.reload.access_token
  end

  test "platform_client는 설정과 토큰 누락을 ArgumentError로 알린다" do
    Preference.stub(:get_object, nil) do
      assert_raises(ArgumentError) { MastodonService.new.send(:platform_client) }
    end
    config = Preference.new(name: "mastodon_oauth", value: { "access_token" => nil })

    Preference.stub(:get_object, config) do
      assert_raises(ArgumentError) { MastodonService.new.send(:platform_client) }
    end
  end


  test "Mastodon은 만료된 토큰도 갱신하거나 저장하지 않는다" do
    config = Preference.create!(name: "mastodon_oauth", value: {
      "site" => "https://social.example", "access_token" => "expired-token",
      "refresh_token" => "old-refresh-token", "expires_at" => 1.hour.ago.to_i
    })
    original_value = config.value.deep_dup
    Preference.stub(:get_object, config) do
      client = MastodonService.new.send(:platform_client)

      assert_equal "Bearer expired-token", client.client.headers["Authorization"]
    end
    assert_equal original_value, config.reload.value
  end
end
