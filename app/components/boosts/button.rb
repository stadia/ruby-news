# typed: true
# frozen_string_literal: true

class Components::Boosts::Button < Components::Base
  include Phlex::Rails::Helpers::ButtonTo
  include Phlex::Rails::Helpers::DOMID
  include PhlexIcons

  def initialize(boostable:, boosted: nil)
    @boostable = boostable
    @boosted = boosted
  end

  def view_template
    div(id: dom_id(@boostable, :boost), class: "inline-flex items-center") do
      boost_button
    end
  end

  private

  def boost_button
    # aria-label을 두면 접근명이 "부스트"로 고정돼 화면에 보이는 카운트("1")를
    # 포함하지 않아 WCAG 2.5.3(label-content-name-mismatch)을 위반한다. sr-only
    # 텍스트 + 카운트로 접근명("부스트 1")이 구성되게 두어 보이는 텍스트를 포함시킨다.
    button_to(
      button_path,
      method: button_method,
      form: { data: { turbo_stream: true }, class: "inline-flex items-center m-0" },
      class: button_classes
    ) do
      span(class: "sr-only") { plain aria_label }
      boost_icon
      span { plain boosts_count.to_s } if boosts_count.positive?
    end
  end

  def aria_label
    boosted? ? t("boosts.button.aria_label.undo") : t("boosts.button.aria_label.boost")
  end

  def boost_icon
    if boosted?
      Hero::ArrowsRightLeftSolid(class: "w-4 h-4")
    else
      Hero::ArrowsRightLeft(variant: :outline, class: "w-4 h-4")
    end
  end

  def boosted?
    return @boosted unless @boosted.nil?

    view_context.current_user&.boosts?(@boostable) || false
  end

  def boosts_count
    @boostable.boosters_count.to_i
  end

  def button_path
    case @boostable
    when Post
      post_boost_path(@boostable)
    when Article
      article_boost_path(@boostable)
    else
      raise ArgumentError, "Unsupported boostable: #{@boostable.class.name}"
    end
  end

  def button_method
    boosted? ? :delete : :post
  end

  def button_classes
    base = "inline-flex items-center gap-1 text-sm transition-colors hover:bg-transparent p-0"
    boosted? ? "#{base} text-success-text" : "#{base} text-content-muted hover:text-success-text"
  end
end
