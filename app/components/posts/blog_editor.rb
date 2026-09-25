# typed: true
# frozen_string_literal: true

class Components::Posts::BlogEditor < Components::Base
  include Phlex::Rails::Helpers::FormWith

  def initialize(post:)
    @post = post
  end

  def view_template
    form_with(model: @post, url: form_url, method: form_method, class: "space-y-5", data: form_data) do |f|
      # New (unsaved) drafts POST to #create; this hidden field lets the autosave
      # controller flip the form to PATCH #update once the draft is persisted.
      input(type: "hidden", name: "_method", value: "post", data: { blog_autosave_target: "methodField" }) unless @post.persisted?

      error_summary
      header
      title_field(f)
      body_field(f)
      footer
    end
  end

  private

  def form_url
    @post.persisted? ? view_context.blog_post_path(@post) : view_context.blog_posts_path
  end

  def form_method
    @post.persisted? ? :patch : :post
  end

  def save_url
    if @post.persisted?
      view_context.blog_post_path(@post, format: :json)
    else
      view_context.blog_posts_path(format: :json)
    end
  end

  def form_data
    {
      controller: "blog-autosave",
      action: "submit->blog-autosave#stop",
      blog_autosave_persisted_value: @post.persisted?,
      blog_autosave_initial_dirty_value: !@post.persisted? && @post.body.present?,
      blog_autosave_save_url_value: save_url,
      blog_autosave_pending_text_value: t("posts.blog.autosave_pending"),
      blog_autosave_saving_text_value: t("posts.blog.autosave_saving"),
      blog_autosave_saved_text_value: t("posts.blog.autosave_saved"),
      blog_autosave_failed_text_value: t("posts.blog.autosave_failed")
    }
  end

  def error_summary
    return unless @post.errors.any?

    div(class: "rounded-lg border border-danger-solid/20 bg-danger-solid/10 p-4 text-sm text-danger-text") do
      ul(class: "list-disc list-inside space-y-1") do
        @post.errors.full_messages.each { |msg| li { msg } }
      end
    end
  end

  def header
    div(class: "flex items-center justify-between gap-3") do
      p(class: "text-sm text-content-muted", data: { blog_autosave_target: "status" }) do
        t("posts.blog.autosave_idle")
      end

      div(class: "flex items-center gap-2") do
        render RubyUI::Button.new(type: :submit, variant: :secondary) { t("posts.blog.preview") }
        publish_button
      end
    end
  end

  def publish_button
    if @post.persisted?
      # formmethod: :post issues a real POST; the _method=patch field then overrides
      # it so the request reaches the `patch :publish` member route.
      render RubyUI::Button.new(
        type: :submit,
        formaction: view_context.publish_blog_post_path(@post),
        formmethod: :post,
        name: "_method",
        value: "patch",
        data: { blog_autosave_target: "publishButton" },
        class: "bg-brand-solid hover:bg-brand-solid-hover text-brand-foreground"
      ) { t("posts.blog.publish") }
    else
      # Unsaved draft: submit to #create with a publish flag so the row is
      # created and published in one request. Once autosave persists the draft,
      # the autosave controller rewires this button to the publish route.
      render RubyUI::Button.new(
        type: :submit,
        formaction: view_context.blog_posts_path,
        formmethod: :post,
        name: "publish",
        value: "1",
        data: { blog_autosave_target: "publishButton" },
        class: "bg-brand-solid hover:bg-brand-solid-hover text-brand-foreground"
      ) { t("posts.blog.publish") }
    end
  end

  def title_field(f)
    f.text_field(
      :title,
      class: "w-full bg-transparent border-0 border-b border-border-muted text-3xl font-bold text-content placeholder:text-content-muted focus:ring-0 focus:border-brand",
      placeholder: t("posts.blog.title_placeholder"),
      data: { action: "input->blog-autosave#markDirty" }
    )
  end

  def body_field(f)
    raw(
      f.lexxy_rich_textarea(
        :body,
        # lexxy-content: Lexxy가 제목·취소선·밑줄·색·인용·목록·코드·표를 그리는
        # 스타일(lexxy-content.css)이 이 클래스 아래에서만 적용된다. class를 직접
        # 넘기면 Lexxy 기본값이 빠지므로 명시한다.
        class: "post-composer-editor lexxy-content w-full min-h-[520px] text-content",
        rows: 18,
        toolbar: true,
        placeholder: t("posts.blog.body_placeholder"),
        autocomplete: "off",
        value: BlogBody.editor_value(@post.body),
        data: {
          action: "lexxy:change->blog-autosave#markDirty input->blog-autosave#markDirty"
        }
      )
    )
  end

  def footer
    div(class: "flex flex-wrap items-center justify-between gap-3 border-t border-border-subtle pt-4 text-sm text-content-muted") do
      span { @post.tag_list.any? ? @post.tag_list.join(", ") : t("posts.blog.no_tags") }
      span { @post.published? ? t("posts.blog.status_published") : t("posts.blog.status_draft") }
    end
  end
end
