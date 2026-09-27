# frozen_string_literal: true

require "application_system_test_case"

class PostDetailsSystemTest < ApplicationSystemTestCase
  setup do
    @reader = users(:jane)
    @blog = posts(:blog_published)
    @short = posts(:root_post)
    @short.update!(slug: "detail-short")
    login_as @reader, scope: :user
  end

  test "blog reactions toggle without replacing the original reading body" do
    visit user_profile_blog_post_path(username: @blog.user.username, slug: @blog)

    within "#like_post_#{@blog.id}" do
      click_button I18n.t("likes.button.aria_label.like")

      assert_button I18n.t("likes.button.aria_label.undo"), exact: false
      click_button I18n.t("likes.button.aria_label.undo"), exact: false

      assert_button I18n.t("likes.button.aria_label.like")
    end

    within "#boost_post_#{@blog.id}" do
      click_button I18n.t("boosts.button.aria_label.boost")

      assert_button I18n.t("boosts.button.aria_label.undo"), exact: false
      click_button I18n.t("boosts.button.aria_label.undo"), exact: false

      assert_button I18n.t("boosts.button.aria_label.boost")
    end

    assert_selector "h1", text: @blog.title
    assert_text "발행된 장문 본문입니다."
  end

  test "both reading pages accept consecutive replies and keep their original body" do
    [ @blog, @short ].each do |root|
      visit detail_path(root)

      2.times do |index|
        fill_lexxy "<p>상세 댓글 #{index}</p>"
        within("#post_form") { click_button I18n.t("posts.post_form.reply_submit") }

        assert_current_path detail_path(root)
        within("#replies_#{root.id}") { assert_text "상세 댓글 #{index}" }
        assert_selector "#post_form input[name='post[parent_id]'][value='#{root.id}']", visible: :all
        assert_selector "h1", text: root.title if root.blog?
      end
    end
  end

  test "replying to a child opens a composer under that reply" do
    visit post_path(@short)
    child = posts(:reply_post)

    open_inline_reply(child)

    assert_selector "#post_#{child.id} + #inline_reply_form"
    assert_selector "#inline_reply_form input[name='post[parent_id]'][value='#{child.id}']", visible: :all
    assert_no_selector "[data-post-form-target='replyBanner']", visible: :all

    fill_lexxy "<p>자식에게 남기는 답글</p>", scope: "#inline_reply_form"
    within("#inline_reply_form") { click_button I18n.t("posts.post_form.reply_submit") }

    # 입력 중인 inline 폼도 같은 글자를 담고 있으므로, 폼이 닫힌 뒤 목록을 본다.
    assert_no_selector "#replies_#{@short.id} #inline_reply_form"
    assert_current_path post_path(@short)
    within("#replies_#{@short.id}") { assert_text "자식에게 남기는 답글" }
    assert_equal child.id, Post.find_by!("body LIKE ?", "%자식에게 남기는 답글%").parent_id
  end

  test "only one inline composer stays open and cancel closes it" do
    child = posts(:reply_post)
    sibling = Post.create!(user: @reader, body: "<p>다른 답글</p>", parent: @short)
    visit post_path(@short)

    open_inline_reply(child)
    open_inline_reply(sibling)

    assert_selector "#inline_reply_form", count: 1
    assert_selector "#post_#{sibling.id} + #inline_reply_form"

    within("#inline_reply_form") { click_button I18n.t("posts.post_form.cancel") }

    assert_no_selector "#inline_reply_form"
    assert_selector "#post_form input[name='post[parent_id]'][value='#{@short.id}']", visible: :all
  end

  test "switching the reply target keeps the draft" do
    child = posts(:reply_post)
    sibling = Post.create!(user: @reader, body: "<p>다른 답글</p>", parent: @short)
    visit post_path(@short)

    open_inline_reply(child)
    fill_lexxy "<p>옮겨 갈 초안</p>", scope: "#inline_reply_form"
    open_inline_reply(child)

    assert_selector "#post_#{child.id} + #inline_reply_form"

    open_inline_reply(sibling)

    assert_selector "#inline_reply_form", count: 1
    assert_selector "#post_#{sibling.id} + #inline_reply_form input[name='post[parent_id]'][value='#{sibling.id}']", visible: :all
    assert_selector "#inline_reply_form .lexxy-editor__content", text: "옮겨 갈 초안", wait: 10

    within("#inline_reply_form") { click_button I18n.t("posts.post_form.reply_submit") }

    assert_no_selector "#replies_#{@short.id} #inline_reply_form"
    assert_equal sibling.id, Post.find_by!("body LIKE ?", "%옮겨 갈 초안%").parent_id
  end

  test "failed inline reply scrolls back to its composer" do
    child = posts(:reply_post)
    visit post_path(@short)

    open_inline_reply(child)
    fill_lexxy "<p><br></p>", scope: "#inline_reply_form"
    within("#inline_reply_form") { click_button I18n.t("posts.post_form.reply_submit") }

    assert_selector "#post_#{child.id} + #inline_reply_form [role='alert']"
    assert_selector "#inline_reply_form .lexxy-editor__content", wait: 10
    assert_predicate evaluate_script("document.querySelector('#inline_reply_form').contains(document.activeElement)"), :present?
  end

  test "cancelling returns focus to the reply button" do
    child = posts(:reply_post)
    visit post_path(@short)

    open_inline_reply(child)
    within("#inline_reply_form") { click_button I18n.t("posts.post_form.cancel") }

    assert_no_selector "#inline_reply_form"
    assert evaluate_script("document.activeElement.closest('#post_#{child.id}') !== null")
  end

  test "reply scrolling respects reduced motion" do
    visit post_path(@short)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])

    assert_equal "auto", evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      import("utils/motion").then(({ scrollBehavior }) => done(scrollBehavior()));
    JS

    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "no-preference" } ])

    assert_equal "smooth", evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      import("utils/motion").then(({ scrollBehavior }) => done(scrollBehavior()));
    JS
  end

  test "replying to the root focuses the reading page composer" do
    visit post_path(@short)

    assert_selector "#post_form .lexxy-editor__content", wait: 10

    open_inline_reply(@short)

    assert_no_selector "#inline_reply_form"
    assert evaluate_script("document.querySelector('#post_form').contains(document.activeElement)")
  end

  test "empty reply keeps the original reading page and validation feedback" do
    visit user_profile_blog_post_path(username: @blog.user.username, slug: @blog)
    fill_lexxy "<p><br></p>"
    within("#post_form") { click_button I18n.t("posts.post_form.reply_submit") }

    assert_selector "h1", text: @blog.title
    assert_selector "#post_form [role='alert']"
    assert_selector "#post_form input[name='post[parent_id]'][value='#{@blog.id}']", visible: :all
  end

  test "rapid repeated submission saves only one reply" do
    visit post_path(@short)
    fill_lexxy "<p>한 번만 저장할 답글</p>"

    execute_script(<<~JS)
      const form = document.querySelector("#post_form form");
      form.requestSubmit();
      form.requestSubmit();
    JS

    assert_current_path post_path(@short)
    within("#replies_#{@short.id}") { assert_text "한 번만 저장할 답글", count: 1 }
    assert_equal 1, Post.where("body LIKE ?", "%한 번만 저장할 답글%").count
  end

  private

  def detail_path(root)
    root.blog? ? user_profile_blog_post_path(username: root.user.username, slug: root) : post_path(root)
  end

  def open_inline_reply(post)
    within("#post_#{post.id}") { find("button[data-action='feed-reply#activate']").click }
  end

  def fill_lexxy(html, scope: "#post_form")
    assert_selector "#{scope} .lexxy-editor__content", wait: 10
    execute_script(<<~JS, find("#{scope} .post-composer-editor"), html)
      const el = arguments[0];
      el.value = arguments[1];
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new CustomEvent("lexxy:change", { bubbles: true }));
    JS
  end
end
