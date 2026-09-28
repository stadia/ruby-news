# frozen_string_literal: true

require "test_helper"

# 어두운 테마의 Lexxy 하이라이트 팔레트(#1025)를 tokens.css 원본에서 읽어 WCAG 대비를 잰다.
# 브라우저 검증과 별도로 팔레트·표면 매핑 및 Lexxy 업그레이드 계약을 빠르게 검증한다.
class HighlightPaletteTest < ActiveSupport::TestCase
  TOKENS = Rails.root.join("app/assets/tailwind/tokens.css").read
  BASE_TOKENS = TOKENS[/^    :root \{(.*?)^    \}/m, 1]
  DARK_TOKENS = TOKENS[/^    :root,\s*\.theme-dark,\s*\.dark \{(.*?)^    \}/m, 1]
  REMAP = TOKENS[/^:root:not\(\.theme-light, \.light\) \{(.*?)^\}/m, 1]
  LEXXY_VARIABLES = Lexxy::Engine.root.join("app/assets/stylesheets/lexxy-variables.css").read
  HIGHLIGHT_NAME = /--highlight(?:-bg)?-\d+/
  SURFACES = %w[--color-bg-primary --color-bg-secondary].freeze
  GAMUT_EPSILON = 0.001 # 소수 셋째 자리 OKLCH 반올림 오차만 허용한다.
  MIN_CONTRAST = 4.5
  HIGHLIGHTS = (1..9).to_a.freeze

  test "어두운 테마에서 루트의 --highlight-*를 시맨틱 토큰으로 다시 정의한다" do
    remap = REMAP

    assert remap, "레이어 밖의 :root:not(.theme-light, .light) 블록이 없다"
    HIGHLIGHTS.each do |n|
      assert_includes remap, "--highlight-#{n}: var(--semantic-highlight-#{n});"
      assert_includes remap, "--highlight-bg-#{n}: var(--semantic-highlight-bg-#{n});"
    end
  end

  test "Lexxy 원본과 어두운 테마 재정의의 하이라이트 이름 집합이 같다" do
    assert_equal highlight_names(LEXXY_VARIABLES).uniq.sort, highlight_names(REMAP).uniq.sort
  end

  test "Lexxy 하이라이트 정의 선택자는 root 하나뿐이다" do
    css = LEXXY_VARIABLES.gsub(%r{/\*.*?\*/}m, "")
    selectors = css.scan(/([^{}]+)\{([^{}]*)\}/).filter_map do |selector, declarations|
      selector.strip if highlight_names(declarations).any?
    end

    assert_equal [ ":root" ], selectors
  end

  test "어두운 테마의 하이라이트 글자는 본문 배경과 모든 배경색 하이라이트 위에서 4.5:1 이상이다" do
    surfaces = SURFACES.map { |name| srgb(token(name)) }
    backgrounds = HIGHLIGHTS.flat_map do |n|
      *color, alpha = srgb(token("--semantic-highlight-bg-#{n}"))
      surfaces.map { |surface| composite(color, alpha, surface) }
    end

    HIGHLIGHTS.each do |n|
      text = srgb(token("--semantic-highlight-#{n}")).first(3)
      worst = (surfaces + backgrounds).map { |background| contrast(text, background) }.min

      assert_operator worst, :>=, MIN_CONTRAST, "--semantic-highlight-#{n} 최저 대비 #{worst.round(2)}"
    end
  end

  test "어두운 테마의 배경색 하이라이트 위 기본 본문 글자는 4.5:1 이상이다" do
    text = srgb(token("--color-text-primary")).first(3)

    HIGHLIGHTS.product(SURFACES) do |n, surface_name|
      *color, alpha = srgb(token("--semantic-highlight-bg-#{n}"))
      background = composite(color, alpha, srgb(token(surface_name)))

      assert_operator contrast(text, background), :>=, MIN_CONTRAST, "--semantic-highlight-bg-#{n} on #{surface_name}"
    end
  end

  private

  def highlight_names(css)
    css.scan(/(#{HIGHLIGHT_NAME.source})\s*:/).flatten
  end

  # 기본 :root와 어두운 테마 블록만 읽고 var() 참조를 따라간다.
  # 밝은 테마에 같은 이름을 추가해도 정의 순서에 영향을 받지 않는다.
  def token(name)
    values = "#{BASE_TOKENS}\n#{DARK_TOKENS}".scan(/(--[\w-]+):\s*([^;]+);/).to_h
    value = values.fetch(name)
    reference = value.match(/\Avar\((--[\w-]+)\)\z/)
    return token(reference[1]) if reference

    match = value.match(/\Aoklch\(([\d.]+) ([\d.]+) ([\d.]+)(?: \/ ([\d.]+))?\)\z/)

    assert match, "#{name} OKLCH 토큰이 없다"
    match.captures.compact.map(&:to_f)
  end

  # OKLCH → sRGB(0..1). 마지막 원소는 알파(없으면 1).
  def srgb((lightness, chroma, hue, alpha))
    a = chroma * Math.cos(hue * Math::PI / 180)
    b = chroma * Math.sin(hue * Math::PI / 180)
    l = (lightness + (0.3963377774 * a) + (0.2158037573 * b))**3
    m = (lightness - (0.1055613458 * a) - (0.0638541728 * b))**3
    s = (lightness - (0.0894841775 * a) - (1.2914855480 * b))**3
    linear = [
      (4.0767416621 * l) - (3.3077115913 * m) + (0.2309699292 * s),
      (-1.2684380046 * l) + (2.6097574011 * m) - (0.3413193965 * s),
      (-0.0041960863 * l) - (0.7034186147 * m) + (1.7076147010 * s)
    ]
    linear.each do |channel|
      assert_operator channel, :>=, -GAMUT_EPSILON, "sRGB 색역 하한 초과: #{linear.inspect}"
      assert_operator channel, :<=, 1 + GAMUT_EPSILON, "sRGB 색역 상한 초과: #{linear.inspect}"
    end
    linear.map { |channel| encode(channel.clamp(0.0, 1.0)) } + [ alpha || 1.0 ]
  end

  def encode(channel)
    channel <= 0.0031308 ? 12.92 * channel : (1.055 * (channel**(1 / 2.4))) - 0.055
  end

  def composite(color, alpha, surface)
    color.zip(surface.first(3)).map { |top, bottom| (top * alpha) + (bottom * (1 - alpha)) }
  end

  def contrast(one, other)
    high, low = [ luminance(one), luminance(other) ].sort.reverse
    (high + 0.05) / (low + 0.05)
  end

  def luminance(rgb)
    red, green, blue = rgb.first(3).map { |c| c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
    (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
  end
end
