# frozen_string_literal: true

require "test_helper"

class BlogSlugTest < ActiveSupport::TestCase
  test "한글 제목은 그대로 두고 공백을 하이픈으로 바꾼다" do
    assert_equal "루비-온-레일즈-시작하기", BlogSlug.normalize("루비 온 레일즈 시작하기")
  end

  test "영문은 소문자로 바꾸고 문장부호·특수문자 연속은 하이픈 하나로 줄인다" do
    assert_equal "hello-world-rails-8-출시", BlogSlug.normalize("  Hello, World!! — Rails 8 출시?! ")
  end

  test "URL 경로를 깨는 문자(/ . ? # %)를 남기지 않는다" do
    assert_equal "a-b-c-d-e-f", BlogSlug.normalize("a/b.c?d#e%f")
  end

  test "NFD로 분해된 한글을 NFC로 합친다" do
    assert_equal "한글", BlogSlug.normalize("한글".unicode_normalize(:nfd))
  end

  test "유효한 문자가 없으면 빈 문자열을 돌려준다" do
    assert_equal "", BlogSlug.normalize("!!! ??? 🎉")
    assert_equal "", BlogSlug.normalize(nil)
  end

  test "긴 제목은 BASE_MAX_LENGTH 글자로 자르고 끝의 하이픈을 떼어낸다" do
    slug = BlogSlug.normalize("가" * 79 + " 나다라마바사")

    assert_equal "가" * 79, slug
    assert_operator BlogSlug.normalize("가" * 200).length, :<=, BlogSlug::BASE_MAX_LENGTH
  end

  test "정규화 결과를 다시 정규화해도 같다" do
    slug = BlogSlug.normalize("Ruby 3.4 — 새 기능")

    assert_equal slug, BlogSlug.normalize(slug)
  end

  test "충돌 회피용 접미사를 붙여도 MAX_LENGTH를 넘지 않는다" do
    candidate = BlogSlug.with_suffix(BlogSlug.normalize("가" * 200))

    assert_match(/\A가+-[0-9a-z]{#{BlogSlug::SUFFIX_LENGTH}}\z/o, candidate)
    assert_operator candidate.length, :<=, BlogSlug::MAX_LENGTH
  end
  test "고립된 결합 문자와 이모지 variation selector를 제거한다" do
    assert_equal "", BlogSlug.normalize("❤️ ☕️ ✈️")
    assert_equal "ruby", BlogSlug.normalize("Ruby ❤️")
    assert_equal "é", BlogSlug.normalize("e\u0301")
    assert_equal "", BlogSlug.normalize("\u0301")
  end

  test "lookup_key는 URL로 들어온 slug를 저장 규칙(NFC·소문자)에 맞춘다" do
    assert_equal "ruby-소식", BlogSlug.lookup_key("RUBY-소식")
    assert_equal "한글-소식", BlogSlug.lookup_key("한글-소식".unicode_normalize(:nfd))
    assert_equal "", BlogSlug.lookup_key(nil)
  end

  test "lookup_key는 절단·기호 치환을 하지 않는다" do
    assert_equal "a_b.c", BlogSlug.lookup_key("A_B.C")
  end

  test "글자 뒤에 붙은 variation selector와 보이지 않는 서식 문자도 제거한다" do
    assert_equal "ruby", BlogSlug.normalize("Ruby\uFE0F")
    assert_equal "ruby-rails", BlogSlug.normalize("Ruby\u200D Ra\u00ADils")
  end
end
