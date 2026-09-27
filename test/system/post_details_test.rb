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

  test "selecting a child reply and cancelling restores the root reply target" do
    visit post_path(@short)
    child = posts(:reply_post)
    label = find("#post_form [data-post-form-target='replyLabel']").text

    within("#post_#{child.id}") { find("button[data-action='feed-reply#activate']").click }

    assert_selector "#post_form input[name='post[parent_id]'][value='#{child.id}']", visible: :all

    within("#post_form") { click_button I18n.t("posts.post_form.cancel") }

    assert_selector "#post_form input[name='post[parent_id]'][value='#{@short.id}']", visible: :all

    assert_selector "#post_form [data-post-form-target='replyLabel']", exact_text: label

    fill_lexxy "<p>루트에 남기는 댓글</p>"
    within("#post_form") { click_button I18n.t("posts.post_form.reply_submit") }

    assert_current_path post_path(@short)
    within("#replies_#{@short.id}") { assert_text "루트에 남기는 댓글" }
    assert_equal @short.id, Post.find_by!("body LIKE ?", "%루트에 남기는 댓글%").parent_id
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

  def fill_lexxy(html)
    assert_selector "#post_form .lexxy-editor__content", wait: 10
    execute_script(<<~JS, find("#post_form .post-composer-editor"), html)
      const el = arguments[0];
      el.value = arguments[1];
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new CustomEvent("lexxy:change", { bubbles: true }));
    JS
  end
end
