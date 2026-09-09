# frozen_string_literal: true

require "test_helper"

class LocalizedDisplayTest < ActiveSupport::TestCase
  setup do
    @article = articles(:ruby_article)
  end

  # ── display_title ──────────────────────────────────────────────────

  test "display_title returns title_ko for ko locale" do
    assert_equal @article.title_ko, @article.display_title(locale: :ko)
  end

  test "display_title falls back to title when title_ko is nil" do
    @article.update_columns(title_ko: nil)

    assert_equal @article.title, @article.display_title(locale: :ko)
  end

  test "display_title returns title_ja for ja locale when present" do
    @article.update_columns(title_ja: "日本語タイトル")

    assert_equal "日本語タイトル", @article.display_title(locale: :ja)
  end

  test "display_title falls back to title_ko when title_ja is nil" do
    @article.update_columns(title_ja: nil)

    assert_equal @article.title_ko, @article.display_title(locale: :ja)
  end

  test "display_title falls back to title when both title_ja and title_ko are nil" do
    @article.update_columns(title_ja: nil, title_ko: nil)

    assert_equal @article.title, @article.display_title(locale: :ja)
  end

  # ── display_summary_key ───────────────────────────────────────────

  test "display_summary_key returns summary_key_ja for ja locale" do
    @article.update_columns(summary_key_ja: [ "要約1", "要約2" ])

    assert_equal [ "要約1", "要約2" ], @article.display_summary_key(locale: :ja)
  end

  test "display_summary_key falls back to ko when ja is nil" do
    @article.update_columns(summary_key_ja: nil)

    assert_equal @article.summary_key, @article.display_summary_key(locale: :ja)
  end

  test "display_summary_key returns ko summary_key by default" do
    assert_equal @article.summary_key, @article.display_summary_key(locale: :ko)
  end

  # ── display_summary_detail ────────────────────────────────────────

  test "display_summary_detail returns ja version when present" do
    @article.update_columns(summary_detail_ja: { "introduction" => "日本語の導入", "conclusion" => "日本語の結論" })
    result = @article.display_summary_detail(locale: :ja)

    assert_equal "日本語の導入", result["introduction"]
  end

  test "display_summary_detail falls back to ko when ja is nil" do
    @article.update_columns(summary_detail_ja: nil)

    assert_equal @article.summary_detail, @article.display_summary_detail(locale: :ja)
  end

  # ── display_summary_body ──────────────────────────────────────────

  test "display_summary_body returns ja version when present" do
    @article.update_columns(summary_body_ja: "日本語の本文")

    assert_equal "日本語の本文", @article.display_summary_body(locale: :ja)
  end

  test "display_summary_body falls back to ko when ja is nil" do
    @article.update_columns(summary_body_ja: nil, summary_body: "한국어 본문")

    assert_equal "한국어 본문", @article.display_summary_body(locale: :ja)
  end

  # ── show_original_title? ───────────────────────────────────────────

  test "show_original_title returns true for ko when title_ko differs from title" do
    assert @article.show_original_title?(locale: :ko)
  end

  test "show_original_title returns false for ko when title_ko matches title" do
    @article.update_columns(title_ko: @article.title)

    assert_not @article.show_original_title?(locale: :ko)
  end

  test "show_original_title returns false for ja when title_ja is nil" do
    @article.update_columns(title_ja: nil)

    assert_not @article.show_original_title?(locale: :ja)
  end

  # ── available_in? ──────────────────────────────────────────────────

  test "available_in? for ja is true when summary_key_ja present" do
    @article.update_columns(summary_key_ja: [ "要約1" ])

    assert @article.available_in?(:ja)
  end

  test "available_in? for ja deserializes a persisted JSONB summary key" do
    @article.update_columns(summary_key_ja: [ "永続化された要約" ])

    assert @article.reload.available_in?(:ja)
  end

  # 번역 완료 신호는 summary_key_ja 이므로, 일본어 원문 제목으로 title_ja 가
  # 미리 채워졌더라도 실제 번역(summary_key_ja) 전에는 :ja 로 노출하지 않는다.
  test "available_in? for ja is false when only title_ja present without summary_key_ja" do
    @article.update_columns(title_ja: "日本語タイトル", summary_key_ja: nil)

    assert_not @article.available_in?(:ja)
  end

  test "available_in? for ko is always true regardless of ja translation" do
    @article.update_columns(summary_key_ja: nil)

    assert @article.available_in?(:ko)
  end

  # ── summary_key_preview ────────────────────────────────────────────

  test "summary_key_preview returns first item of array" do
    @article.update_columns(summary_key: [ "첫 번째", "두 번째" ])

    assert_equal "첫 번째", @article.summary_key_preview
  end

  test "summary_key_preview returns string as-is" do
    @article.update_columns(summary_key: "단일 요약")

    assert_equal "단일 요약", @article.summary_key_preview
  end

  test "summary_key_preview respects locale for ja" do
    @article.update_columns(summary_key_ja: [ "要約第一", "要約第二" ])

    assert_equal "要約第一", @article.summary_key_preview(locale: :ja)
  end
end
