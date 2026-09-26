# frozen_string_literal: true

require "application_system_test_case"

class BlogPostsTest < ApplicationSystemTestCase
  setup do
    @user = users(:john)
    login_as @user, scope: :user
  end

  test "user creates and publishes a blog post" do
    visit feed_path

    # 컴포저의 "장문 쓰기" 버튼이 초안을 만들고 편집기를 연다.
    click_button I18n.t("posts.post_form.blog")

    # 편집기 진입(헤딩은 sr-only h1, 텍스트로 확인 가능).
    assert_text I18n.t("posts.blog.edit_heading")

    # 제목 입력: form_with model: @post 가 :title 에 대해 id="post_title" 를 생성.
    fill_in "post_title", with: "시스템 테스트 장문"

    # Lexxy 본문 입력: <lexxy-editor> 커스텀 엘리먼트는 form-associated 이며
    # JS `value` setter 가 내부 Lexical 에디터와 폼 값을 동기화한다.
    # contenteditable 영역(.lexxy-editor__content)이 나타나길 기다린 뒤 value 를 설정한다.
    fill_lexxy ".post-composer-editor", "<p>시스템 테스트 본문입니다.</p>"

    click_button I18n.t("posts.blog.publish")

    # 발행 후 읽기 레이아웃 원문 페이지로 리다이렉트된다.
    assert_text "시스템 테스트 장문"
    assert_text "시스템 테스트 본문입니다."

    # 프로필 포스트 목록에도 발행된 장문이 노출된다.
    visit user_profile_posts_path(username: @user.username)

    assert_text "시스템 테스트 장문"

    # 프로필 카드(activity-list 터보 프레임 안)에서 "원문 읽기"를 눌러도
    # data-turbo-frame="_top" 덕분에 전체 페이지로 원문이 정상 열린다.
    click_link I18n.t("posts.blog.read_more"), match: :first

    assert_text "시스템 테스트 본문입니다."
  end

  test "toolbar formatting survives saving and re-editing" do
    draft = posts(:blog_draft)
    # 툴바 버튼마다 Lexxy 0.9.33이 실제로 내보내는 HTML.
    formatted = <<~HTML.delete("\n")
      <h2>큰 제목</h2>
      <p>a <s>취소선</s> <u>밑줄</u> <mark style="color: var(--highlight-1);">글자색</mark>
      <mark style="background-color: var(--highlight-bg-1);">배경색</mark></p>
      <pre data-language="ruby" data-highlight-language="ruby">puts 1</pre>
      <figure class="lexxy-content__table-wrapper"><table><tbody><tr>
      <th class="lexxy-content__table-cell--header"><p>머리</p></th><td><p>칸</p></td>
      </tr></tbody></table></figure>
      <p>본문 끝</p>
    HTML

    visit edit_blog_post_path(draft)
    fill_lexxy ".post-composer-editor", formatted

    2.times do |round|
      if round.positive?
        visit edit_blog_post_path(draft)

        assert_selector ".post-composer-editor .lexxy-editor__content", wait: 10
        find(".post-composer-editor .lexxy-editor__content p", text: "본문 끝").click
        send_keys :end, "!"
      end

      click_button I18n.t("posts.blog.preview")

      assert_no_selector "lexxy-editor", wait: 10
      within ".post-content" do
        assert_selector "h2", text: "큰 제목"
        assert_selector "s", text: "취소선"
        assert_selector "u", text: "밑줄"
        assert_selector "mark[style='color: var(--highlight-1);']", text: "글자색"
        assert_selector "mark[style='background-color: var(--highlight-bg-1);']", text: "배경색"
        assert_selector "pre[data-language='ruby']", text: "puts 1"
        assert_selector "table th", text: "머리"
        assert_selector "table td", text: "칸"
      end
    end
  end

  test "owner re-opens a draft, edits, and deletes a published post" do
    draft = posts(:blog_draft)

    # 초안은 프로필의 "장문" 탭(작성 중 초안 섹션)에 편집기 링크로 노출된다.
    # 이 영역은 프로필의 "activity-list" 터보 프레임 안에 있지만, 링크에
    # data-turbo-frame="_top" 이 있어 클릭 시 전체 페이지 네비게이션으로
    # 편집기가 정상적으로 열린다.
    visit account_blog_path
    click_link draft.title

    assert_text I18n.t("posts.blog.edit_heading")
    # 초안 본문이 편집기에 다시 로드된다.
    assert_text "초안 본문입니다."

    # 발행 장문을 원문 페이지에서 삭제(soft discard)하면 목록에서 사라진다.
    visit user_profile_blog_post_path(username: @user.username, slug: posts(:blog_published))
    accept_confirm { click_button I18n.t("posts.blog.delete") }

    # 삭제 후 프로필 목록에서 해당 발행 장문이 더 이상 보이지 않는다.
    visit user_profile_posts_path(username: @user.username)

    assert_no_text posts(:blog_published).title
  end

  test "editing a post with a captioned image does not duplicate the caption" do
    draft = posts(:blog_draft)
    draft.update!(body: %(<figure><img src="/favicon-32x32.png" alt="대체 텍스트"><figcaption>사진 설명</figcaption></figure><p>본문 끝</p>))

    2.times do |round|
      visit edit_blog_post_path(draft)

      assert_selector ".post-composer-editor .lexxy-editor__content", wait: 10

      # Lexxy가 본문을 다시 직렬화하도록 실제로 한 글자 고친다.
      find(".post-composer-editor .lexxy-editor__content p", text: "본문 끝").click
      send_keys :end, round.to_s

      click_button I18n.t("posts.blog.preview")

      assert_no_selector "lexxy-editor", wait: 10
      assert_selector "figcaption", text: "사진 설명", count: 1

      body = Nokogiri::HTML5.fragment(draft.reload.body)

      assert_equal 1, body.css("figure img").size, draft.body
      assert_equal [ "사진 설명" ], body.css("figcaption").map(&:text)
      assert_equal [ "본문 끝#{(0..round).to_a.join}" ], body.css("p").map(&:text), draft.body
    end
  end

  private

  # Lexxy 커스텀 엘리먼트를 구동한다. `<lexxy-editor>` 는 form-associated 이고
  # JS `value` setter 가 폼 값(setFormValue)을 채운다. `.set`/`fill_in` 은 커스텀
  # 엘리먼트에 동작하지 않으므로 에디터가 초기화된 뒤 value 프로퍼티를 직접 설정한다.
  def fill_lexxy(selector, html)
    assert_selector "#{selector} .lexxy-editor__content", wait: 10
    execute_script(<<~JS, find(selector), html)
      const el = arguments[0];
      el.value = arguments[1];
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new CustomEvent("lexxy:change", { bubbles: true }));
    JS
  end
end
