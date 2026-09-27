# typed: true
# frozen_string_literal: true

class Components::Posts::PostForm < Components::Base
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::HiddenFieldTag
  include PhlexIcons

  # 상세(thread_post 있음)는 답글 대상을 배너 없이 폼 위치로 알린다.
  # inline: true는 하위 답글 아래에 끼워 넣는 폼으로, id와 필드 id를 inline_reply_*로
  # 바꾸고 취소 버튼을 단다. 배치는 Views::Posts::Show와 thread-reply가 맡는다.
  def initialize(post: Post.new, thread_post: nil, inline: false)
    @post = post
    @thread_post = thread_post
    @inline = inline
  end

  def view_template
    div(
      id: @inline ? "inline_reply_form" : "post_form",
      class: @inline ? nil : "mb-6",
      data: {
        controller: "character-counter post-form",
        post_form_default_parent_id_value: @thread_post && !@inline ? @thread_post.id : nil,
        character_counter_max_length_value: ::Post::MAX_BODY_LENGTH.to_s,
        action: form_actions
      }
    ) do
      render RubyUI::Card.new(class: "bg-surface border-border-muted shadow-sm") do
        render RubyUI::CardContent.new(class: "p-4 sm:p-5") do
          form_with(
            model: @post,
            url: view_context.posts_path,
            class: "space-y-3",
            autocomplete: "off",
            # 상세는 전체 스레드를 다시 렌더링해 실패한 입력과 오류를 보존한다.
            data: { turbo: @thread_post.nil? }
          ) do |f|
            hidden_field_tag :return_to_post, @thread_post.id, id: field_id("return_to_post") if @thread_post
            error_messages if @post.errors.any?
            reply_state_banner unless @thread_post
            f.hidden_field :parent_id, value: @post.parent_id, id: field_id("parent_id"), data: { post_form_target: "parentId" }
            body_field(f)
            form_footer(f)
          end
        end
      end
    end
  end

  private

  # 피드만 카드의 답글 이벤트로 대상을 바꾼다. 상세는 thread-reply가 폼을 연다.
  def form_actions
    actions = "submit->post-form#submit turbo:submit-end->post-form#reset"
    @thread_post ? actions : "#{actions} post-form:reply@window->post-form#activateReply"
  end

  def field_id(name)
    @inline ? "inline_reply_#{name}" : "post_#{name}"
  end

  def error_messages
    div(class: "text-sm text-danger-text", role: "alert") do
      @post.errors.full_messages.each { |msg| p { msg } }
    end
  end

  def body_field(f)
    if @thread_post
      render RubyUI::FormFieldLabel.new(for: field_id("body"), class: "sr-only") { t("posts.show.reply_body") }
    end
    raw(
      f.lexxy_rich_textarea(
        :body,
        id: field_id("body"),
        class: "post-composer-editor w-full text-content",
        rows: 3,
        toolbar: false,
        attachments: "false",
        placeholder: t("helpers.placeholder.post.body"),
        autocomplete: "off",
        data: {
          post_form_target: "body",
          character_counter_target: "input",
          action: "lexxy:change->character-counter#update lexxy:initialize->character-counter#update"
        }
      )
    )
  end

  def reply_state_banner
    div(class: reply_banner_classes, data: { post_form_target: "replyBanner" }) do
      div(class: "flex items-center justify-between gap-3") do
        p(class: "text-sm text-content-secondary") do
          plain t("posts.post_form.replying_to")
          if reply_target_label.present?
            plain ": "
            span(class: "font-medium text-content", data: { post_form_target: "replyLabel" }) { reply_target_label }
          else
            span(class: "font-medium text-content", data: { post_form_target: "replyLabel" })
          end
        end

        render RubyUI::Button.new(
          type: :button,
          variant: :ghost,
          size: :sm,
          data: { action: "post-form#cancelReply" },
          class: "text-content-muted hover:text-content hover:bg-transparent"
        ) { t("posts.post_form.cancel") }
      end

      p(class: "mt-2 text-sm text-content-muted wrap-break-word", data: { post_form_target: "replyPreview" }) do
        plain reply_preview_text.to_s
      end
    end
  end

  def form_footer(f)
    div(class: "flex items-center justify-between") do
      div(class: "text-xs text-content-muted") do
        span(data: { character_counter_target: "counter" }) { "0" }
        plain "/#{::Post::MAX_BODY_LENGTH}"
      end
      div(class: "flex items-center gap-2") do
        # 상세 inline 폼만: thread-reply가 폼을 지우고 답글 버튼으로 포커스를 돌린다.
        if @inline
          render RubyUI::Button.new(
            type: :button,
            variant: :ghost,
            data: { action: "thread-reply#close" }
          ) { t("posts.post_form.cancel") }
        end
        # Opens the blog editor carrying the in-progress body. POSTs to #new so
        # the body travels in the request body (not the URL); #new stashes it and
        # redirects to the GET editor, which Turbo renders. The draft row is
        # created lazily on first autosave — switching to blog from an empty
        # composer never persists an empty draft.
        unless @thread_post
          render RubyUI::Button.new(
            type: :submit,
            formaction: view_context.new_blog_post_path,
            formmethod: :post,
            variant: :secondary,
            class: "text-content-secondary"
          ) { t("posts.post_form.blog") }
        end
        f.submit submit_label,
          class: "inline-flex items-center px-5 py-2 bg-info-solid hover:bg-info-solid-hover text-brand-foreground text-sm font-medium rounded-lg transition-colors duration-200 cursor-pointer"
      end
    end
  end

  def reply_banner_classes
    classes = [ "hidden rounded-lg border border-border-muted bg-surface-muted px-3 py-2" ]
    classes.delete("hidden") if @post.parent_id.present?
    classes.join(" ")
  end

  def submit_label
    @post.parent_id.present? ? t("posts.post_form.reply_submit") : t("posts.post_form.post_submit")
  end

  def reply_target_label
    return unless parent_post.present?

    author_label(parent_post)
  end

  def author_label(post)
    post.user&.name || post.fedipub_actor&.name || post.author_name
  end

  def reply_preview_text
    return unless parent_post.present?

    view_context.truncate(view_context.strip_tags(parent_post.body.to_s).squish, length: 120)
  end

  def parent_post
    return @parent_post if defined?(@parent_post)
    return @parent_post = nil if @post.parent_id.blank?

    @parent_post = Post.visible.includes(:user, :fedipub_actor).find_by(id: @post.parent_id)
  end
end
