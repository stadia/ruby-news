# frozen_string_literal: true

require "application_system_test_case"

# Lexxy 글자색·배경색(<mark style="…var(--highlight-…)">)이 어두운 테마의 본문 배경
# 위에서 WCAG AA(4.5:1)를 넘는지 브라우저가 실제로 계산한 색으로 확인한다(#1025).
class HighlightContrastTest < ApplicationSystemTestCase
  MIN_CONTRAST = 4.5
  COLORS = (1..9).map { |n| "color: var(--highlight-#{n});" }.freeze
  BACKGROUNDS = (1..9).map { |n| "background-color: var(--highlight-bg-#{n});" }.freeze
  # 글자색만, 배경색만(기본 본문 글자), 글자색 × 배경색 조합 전부.
  STYLES = (COLORS + BACKGROUNDS + COLORS.product(BACKGROUNDS).map { |pair| pair.join(" ") }).freeze
  HIGHLIGHTED_BODY = STYLES.map { |style| %(<p><mark style="#{style}">색 글자</mark></p>) }.join.freeze

  # 캔버스에 칠해 브라우저가 해석한 sRGB 값을 읽는다. 배경색 하이라이트는 반투명이라
  # 표면색 위에 겹쳐 칠한 결과로 대비를 잰다.
  CONTRASTS_SCRIPT = <<~JS
    const ctx = Object.assign(document.createElement("canvas"), { width: 1, height: 1 })
      .getContext("2d", { willReadFrequently: true });
    const paint = (...colors) => {
      ctx.clearRect(0, 0, 1, 1);
      colors.forEach((color) => { ctx.fillStyle = color; ctx.fillRect(0, 0, 1, 1); });
      return Array.from(ctx.getImageData(0, 0, 1, 1).data).slice(0, 3);
    };
    const luminance = (rgb) => {
      const [r, g, b] = rgb.map((v) => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    };
    const ratio = (a, b) => {
      const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
      return (hi + 0.05) / (lo + 0.05);
    };
    const surface = getComputedStyle(document.querySelector(surfaceSelector)).backgroundColor;
    return Array.from(document.querySelectorAll(markSelector), (mark) => {
      const style = getComputedStyle(mark);
      const background = paint(surface, style.backgroundColor);
      const foreground = paint(surface, style.backgroundColor, style.color);
      return [mark.getAttribute("style"), Math.round(ratio(foreground, background) * 100) / 100];
    });
  JS

  setup do
    @user = users(:john)
  end

  test "어두운 테마의 글 화면에서 하이라이트 글자는 본문 배경 대비 4.5:1 이상이다" do
    post = posts(:blog_published)
    post.update!(body: HIGHLIGHTED_BODY)

    visit_in_dark_theme user_profile_blog_post_path(username: @user.username, slug: post)

    assert_readable highlight_contrasts(".post-content mark", "article:has(.post-content)")
  end

  test "어두운 테마의 편집기에서 하이라이트 글자는 편집기 배경 대비 4.5:1 이상이다" do
    login_as @user, scope: :user
    draft = posts(:blog_draft)
    draft.update!(body: HIGHLIGHTED_BODY)

    visit_in_dark_theme edit_blog_post_path(draft)

    assert_selector ".post-composer-editor .lexxy-editor__content mark", minimum: STYLES.size, wait: 10
    assert_readable highlight_contrasts(".post-composer-editor .lexxy-editor__content mark", "lexxy-editor.post-composer-editor")
  end

  private

  def visit_in_dark_theme(path)
    visit path
    page.execute_script("localStorage.theme = 'dark'")
    page.refresh

    assert_selector "html.theme-dark"
  end

  def highlight_contrasts(mark_selector, surface_selector)
    page.evaluate_script(<<~JS, mark_selector, surface_selector)
      (function(markSelector, surfaceSelector) { #{CONTRASTS_SCRIPT} })(arguments[0], arguments[1])
    JS
  end

  def assert_readable(contrasts)
    assert_equal STYLES.sort, contrasts.map(&:first).sort
    low = contrasts.select { |_style, ratio| ratio < MIN_CONTRAST }

    assert_empty low, "4.5:1 미달 하이라이트: #{low.inspect}"
  end
end
