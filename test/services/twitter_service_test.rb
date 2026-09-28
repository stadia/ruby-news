# frozen_string_literal: true

# rbs_inline: enabled

require "test_helper"

class TwitterServiceTest < ActiveSupport::TestCase
  # Twitter 포스팅/삭제 기능을 mock을 사용하여 테스트

  # MockResponse 헬퍼 Struct
  MockResponse = Struct.new(:status, :body, keyword_init: true)

  setup do
    @article = articles(:ruby_article)
    @article.update(twitter_id: nil) # 포스팅 전 상태로 초기화

    # 태그 연결 설정
    @article.tags << tags(:ruby_tag) unless @article.tags.include?(tags(:ruby_tag))
    @article.tags << tags(:rails_tag) unless @article.tags.include?(tags(:rails_tag))
  end

  # 성공적인 포스팅 테스트
  test "post_to_platform은 성공 시 twitter_id를 저장한다" do
    mock_response = MockResponse.new(status: 200, body: { "data" => { "id" => "1234567890" } })

    mock_client = Object.new
    mock_client.define_singleton_method(:post) { |_| mock_response }

    service = TwitterService.new

    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :post)

      assert_predicate result, :success?
      assert_equal "1234567890", result.value!
    end

    @article.reload

    assert_equal "1234567890", @article.twitter_id
  end

  # 이미 포스팅된 기사는 실패해야 함
  test "post_to_platform은 이미 포스팅된 기사의 경우 failure를 반환한다" do
    @article.update(twitter_id: "existing_id")

    service = TwitterService.new

    # platform_client가 호출되지 않아야 함
    mock_client = Object.new
    mock_client.define_singleton_method(:post) { |_| raise "Should not be called" }

    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :post)

      assert_predicate result, :failure?
      assert_equal :already_posted, result.failure
    end
  end

  # API 에러 시 실패 처리
  test "post_to_platform은 API 에러 시 failure를 반환한다" do
    mock_response = MockResponse.new(status: 403, body: {})

    mock_client = Object.new
    mock_client.define_singleton_method(:post) { |_| mock_response }

    service = TwitterService.new

    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :post)

      assert_predicate result, :failure?
      assert_equal 403, result.failure
    end
  end

  # 삭제 성공 테스트
  test "delete_from_platform은 성공 시 twitter_id를 nil로 설정한다" do
    @article.update(twitter_id: "1234567890")

    mock_response = MockResponse.new(status: 200, body: {})

    mock_client = Object.new
    mock_client.define_singleton_method(:delete) { |_| mock_response }

    service = TwitterService.new

    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :delete)

      assert_predicate result, :success?
      assert_equal @article.id, result.value!
    end

    @article.reload

    assert_nil @article.twitter_id
  end

  # twitter_id가 없는 기사 삭제 시도
  test "delete_from_platform은 twitter_id가 없으면 failure를 반환한다" do
    @article.update(twitter_id: nil)

    service = TwitterService.new
    mock_client = Object.new
    mock_client.define_singleton_method(:delete) { |_| raise "Should not be called" }

    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :delete)

      assert_predicate result, :failure?
      assert_equal :no_social_id, result.failure
    end
  end

  # Ruby 관련이 아닌 기사는 포스팅하지 않음
  test "should_post_article?은 is_related가 false인 기사를 건너뛴다" do
    @article.update(is_related: false)

    service = TwitterService.new
    mock_client = Object.new
    mock_client.define_singleton_method(:post) { |_| raise "Should not be called" }

    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :post)

      assert_predicate result, :failure?
      assert_equal :not_suitable, result.failure
    end
  end

  # slug가 없는 기사는 포스팅하지 않음
  test "should_post_article?은 slug가 없는 기사를 건너뛴다" do
    @article.update(slug: nil)

    service = TwitterService.new
    mock_client = Object.new
    mock_client.define_singleton_method(:post) { |_| raise "Should not be called" }

    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :post)

      assert_predicate result, :failure?
      assert_equal :not_suitable, result.failure
    end
  end

  # title_ko가 없는 기사는 포스팅하지 않음
  test "should_post_article?은 title_ko가 없는 기사를 건너뛴다" do
    @article.update(title_ko: nil)

    service = TwitterService.new
    mock_client = Object.new
    mock_client.define_singleton_method(:post) { |_| raise "Should not be called" }

    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :post)

      assert_predicate result, :failure?
      assert_equal :not_suitable, result.failure
    end
  end

  # 잘못된 command 처리
  test "call은 알 수 없는 command에 대해 ArgumentError를 발생시킨다" do
    service = TwitterService.new

    assert_raises(ArgumentError) do
      service.call(@article, command: :invalid)
    end
  end

  # 포스트 텍스트 생성 테스트
  test "build_post_text는 280자 이내의 텍스트를 생성한다" do
    service = TwitterService.new

    # private 메서드이므로 send를 사용
    post_text = service.send(:build_post_text, @article)

    # Twitter 제한 280자 확인 (URL 단축 고려)
    assert_operator post_text.length, :<=, 280 + 23, "포스트 텍스트가 너무 깁니다: #{post_text.length}자"
    assert_includes post_text, @article.title_ko
    assert_includes post_text, "ruby-news.dev"
  end

  # 태그가 확인된 것만 사용하는지 테스트
  test "build_post_text는 확인된 태그만 사용한다" do
    # 확인되지 않은 태그 추가
    unconfirmed_tag = tags(:new_feature_tag)
    @article.tags << unconfirmed_tag unless @article.tags.include?(unconfirmed_tag)

    service = TwitterService.new
    post_text = service.send(:build_post_text, @article)

    # 확인된 태그(ruby_tag)는 포함되어야 함
    assert_includes post_text, "#ruby", "확인된 태그가 포함되어야 합니다"
    # 확인되지 않은 태그는 포함되지 않아야 함
    refute_includes post_text, "#new-features", "확인되지 않은 태그는 포함되지 않아야 합니다"
  end

  # 가장 taggings_count가 높은 태그 하나만 사용
  test "build_post_text는 taggings_count가 가장 높은 태그 하나만 사용한다" do
    service = TwitterService.new
    post_text = service.send(:build_post_text, @article)

    # ruby_tag(5)가 rails_tag(3)보다 taggings_count가 높음
    assert_includes post_text, "#ruby"
    # 다른 태그는 포함되지 않아야 함 (Twitter는 하나만 사용)
    tag_count = post_text.scan(/#\w+/).count

    assert_equal 1, tag_count, "Twitter 포스트에는 태그가 하나만 있어야 합니다"
  end

  # platform_name 테스트
  test "platform_name은 X.com을 반환한다" do
    service = TwitterService.new

    assert_equal "X.com", service.send(:platform_name)
  end

  # API 500 에러 처리 테스트
  test "post_to_platform은 500 에러 시 failure를 반환한다" do
    mock_response = MockResponse.new(status: 500, body: {})

    mock_client = Object.new
    mock_client.define_singleton_method(:post) { |_| mock_response }

    service = TwitterService.new

    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :post)

      assert_predicate result, :failure?
      assert_equal 500, result.failure
    end
  end

  # 삭제 API 에러 처리 테스트
  test "delete_from_platform은 API 에러 시 failure를 반환한다" do
    @article.update(twitter_id: "1234567890")

    mock_response = MockResponse.new(status: 404, body: {})

    mock_client = Object.new
    mock_client.define_singleton_method(:delete) { |_| mock_response }

    service = TwitterService.new

    service.stub(:platform_client, mock_client) do
      result = service.call(@article, command: :delete)

      assert_predicate result, :failure?
      assert_equal 404, result.failure
    end
  end

  test "platform_client는 Preference 설정을 조회해 전달한다" do
    config = Preference.create!(name: "xcom_oauth", value: {
      "site" => "https://social.example", "client_id" => "test-id", "client_secret" => "test-secret",
      "access_token" => "test-access-token", "refresh_token" => "test-refresh-token",
      "expires_at" => 1.hour.from_now.to_i
    })
    Preference.stub(:get_object, ->(key) { assert_equal "xcom_oauth", key; config }) do
      config.stub(:update, ->(*) { flunk "만료되지 않은 토큰은 저장하지 않아야 합니다" }) do
        client = TwitterService.new.send(:platform_client)

        assert_equal "Bearer test-access-token", client.client.headers["Authorization"]
      end
    end

    assert_equal "test-access-token", config.reload.access_token
  end

  test "platform_client는 설정과 토큰 누락을 ArgumentError로 알린다" do
    Preference.stub(:get_object, nil) do
      assert_raises(ArgumentError) { TwitterService.new.send(:platform_client) }
    end
    config = Preference.new(name: "xcom_oauth", value: { "access_token" => nil })

    Preference.stub(:get_object, config) do
      assert_raises(ArgumentError) { TwitterService.new.send(:platform_client) }
    end
  end


  test "만료된 토큰은 클라이언트 생성 전에 갱신하고 저장한다" do
    config = Preference.create!(name: "xcom_oauth", value: {
      "client_id" => "test-id", "client_secret" => "test-secret",
      "access_token" => "expired-token", "refresh_token" => "old-refresh-token",
      "expires_at" => 1.hour.ago.to_i
    })
    oauth_client = OauthClient.build(config)
    refresh_stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/2/oauth2/token") do |env|
        body = URI.decode_www_form(env.body).to_h

        assert_equal "refresh_token", body["grant_type"]
        assert_equal "old-refresh-token", body["refresh_token"]
        [ 200, { "Content-Type" => "application/json" }, {
          access_token: "refreshed-token", refresh_token: "new-refresh-token", expires_in: 3600
        }.to_json ]
      end
    end
    oauth_client.connection.adapter(:test, refresh_stubs)
    post_stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/2/tweets") do |env|
        assert_equal "Bearer refreshed-token", env.request_headers["Authorization"]
        [ 200, { "Content-Type" => "application/json" }, "{}" ]
      end
    end

    Preference.stub(:get_object, config) do
      OauthClient.stub(:build, oauth_client) do
        client = TwitterService.new.send(:platform_client)

        assert_equal "refreshed-token", config.reload.access_token
        assert_equal "new-refresh-token", config.refresh_token
        assert_operator config.expires_at, :>, Time.current.to_i
        client.client.adapter(:test, post_stubs)
        client.post("테스트")
      end
    end

    refresh_stubs.verify_stubbed_calls
    post_stubs.verify_stubbed_calls
  end

  test "토큰 갱신 실패 시 기존 설정을 저장하거나 클라이언트를 생성하지 않는다" do
    config = Preference.create!(name: "xcom_oauth", value: {
      "client_id" => "test-id", "client_secret" => "test-secret",
      "access_token" => "expired-token", "refresh_token" => "old-refresh-token",
      "expires_at" => 1.hour.ago.to_i
    })
    original_value = config.value.deep_dup
    oauth_client = OauthClient.build(config)
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/2/oauth2/token") { [ 400, { "Content-Type" => "application/json" }, '{"error":"invalid_grant"}' ] }
    end
    oauth_client.connection.adapter(:test, stubs)

    Preference.stub(:get_object, config) do
      OauthClient.stub(:build, oauth_client) do
        config.stub(:update, ->(*) { flunk "갱신 실패 시 저장하지 않아야 합니다" }) do
          stub_constructor(TwitterClient, ->(*) { flunk "갱신 실패 시 클라이언트를 생성하지 않아야 합니다" }) do
            assert_raises(OAuth2::Error) { TwitterService.new.send(:platform_client) }
          end
        end
      end
    end

    assert_equal original_value, config.reload.value
    stubs.verify_stubbed_calls
  end
end
