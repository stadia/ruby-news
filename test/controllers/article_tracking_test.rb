# frozen_string_literal: true

require "test_helper"

class ArticleTrackingTest < ActionDispatch::IntegrationTest
  BROWSER = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

  test "HTML article views record the article and an anonymous visit" do
    article = articles(:ruby_article)

    assert_difference [ "Ahoy::Event.count", "Ahoy::Visit.count" ], 1 do
      get article_path(article), headers: { "User-Agent" => BROWSER }
    end

    assert_response :success
    event = Ahoy::Event.last

    assert_equal "Viewed article", event.name
    assert_equal({ "article_id" => article.id }, event.properties)
    assert_nil event.user_id
    assert_equal event.visit_id, Ahoy::Visit.last.id
  end

  test "negotiated HTML views are tracked when HTML is not the first accepted format" do
    assert_difference "Ahoy::Event.count", 1 do
      get article_path(articles(:ruby_article)), headers: { "User-Agent" => BROWSER, "Accept" => "application/json, text/html" }
    end

    assert_response :success
    assert_equal "text/html", response.media_type
  end

  test "signed in article views are attributed to the current user" do
    sign_in_as users(:john)

    assert_difference "Ahoy::Event.count", 1 do
      get article_path(articles(:ruby_article)), headers: { "User-Agent" => BROWSER }
    end

    assert_equal users(:john), Ahoy::Event.last.user
    assert_equal users(:john), Ahoy::Visit.last.user
  end

  test "repeated views create separate events in the same visit" do
    2.times do
      get article_path(articles(:ruby_article)), headers: { "User-Agent" => BROWSER }
    end

    assert_equal 2, Ahoy::Event.count
    assert_equal 1, Ahoy::Visit.count
  end

  test "unrelated pages do not create visits or tracking cookies" do
    assert_no_difference [ "Ahoy::Event.count", "Ahoy::Visit.count" ] do
      get root_path, headers: { "User-Agent" => BROWSER }

      assert_response :success
      assert_select "a[href=?][data-turbo-prefetch='false']", article_path(articles(:ruby_article))
      get articles_path, headers: { "User-Agent" => BROWSER }
    end

    assert_response :success
    assert_nil cookies[:ahoy_visit]
    assert_nil cookies[:ahoy_visitor]
    assert_equal [ "max-age=300", "public" ], response.headers["Cache-Control"].split(", ").sort
  end

  test "HEAD and markdown requests do not create tracking records" do
    assert_no_difference [ "Ahoy::Event.count", "Ahoy::Visit.count" ] do
      head article_path(articles(:ruby_article)), headers: { "User-Agent" => BROWSER }

      assert_response :success
      get article_path(articles(:ruby_article), format: :md), headers: { "User-Agent" => BROWSER }

      assert_response :success
    end
  end

  test "prefetch requests do not create tracking records" do
    [ { "X-Sec-Purpose" => "prefetch" }, { "Sec-Purpose" => "prefetch;prerender" }, { "Purpose" => "prefetch" } ].each do |headers|
      assert_no_difference [ "Ahoy::Event.count", "Ahoy::Visit.count" ] do
        get article_path(articles(:ruby_article)), headers: headers.merge("User-Agent" => BROWSER)

        assert_response :success
      end
    end
  end

  test "bots do not create tracking records" do
    assert_no_difference [ "Ahoy::Event.count", "Ahoy::Visit.count" ] do
      get article_path(articles(:ruby_article)), headers: { "User-Agent" => "Googlebot/2.1 (+http://www.google.com/bot.html)" }
    end
    assert_response :success
  end

  test "missing discarded and unsupported articles do not create tracking records" do
    assert_no_difference [ "Ahoy::Event.count", "Ahoy::Visit.count" ] do
      get article_path("missing-article"), headers: { "User-Agent" => BROWSER }

      assert_response :not_found
      get article_path(articles(:deleted_article)), headers: { "User-Agent" => BROWSER }

      assert_response :not_found
      get article_path(articles(:ruby_article), format: :json), headers: { "User-Agent" => BROWSER }

      assert_response :not_acceptable
    end
  end
end
