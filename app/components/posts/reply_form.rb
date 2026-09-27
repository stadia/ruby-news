# typed: true
# frozen_string_literal: true

class Components::Posts::ReplyForm < Components::Base
  include Phlex::Rails::Helpers::FormWith
  include PhlexIcons

  def initialize(parent_post:)
    @parent_post = parent_post
  end

  def view_template
    div(
      class: "ml-4 sm:ml-8",
      data: {
        controller: "character-counter",
        character_counter_max_length_value: "500"
      }
    ) do
      form_with(
        model: Post.new,
        url: view_context.posts_path,
        class: "space-y-2",
        data: { action: "turbo:submit-end->reply-form#close" }
      ) do |f|
        f.hidden_field :parent_id, value: @parent_post.id

        f.text_area :body,
          rows: 2,
          class: "w-full px-3 py-2 rounded-lg border border-input bg-surface text-content placeholder:text-content-muted hover:border-content-muted focus:border-transparent focus:ring-2 focus:ring-state-info transition-all duration-200 resize-none text-sm",
          placeholder: t("helpers.placeholder.post.reply_body"),
          data: { character_counter_target: "input", action: "input->character-counter#update" }

        div(class: "flex items-center justify-between") do
          div(class: "text-xs text-content-muted") do
            span(data: { character_counter_target: "counter" }) { "0" }
            plain t("posts.reply_form.char_unit")
          end
          div(class: "flex items-center gap-2") do
            render RubyUI::Button.new(
              variant: :ghost,
              size: :sm,
              data: { action: "reply-form#toggle" },
              class: "text-content-muted hover:text-content text-xs hover:bg-transparent"
            ) { t("posts.reply_form.cancel") }
            f.submit t("posts.reply_form.submit"),
              class: "inline-flex items-center px-4 py-1.5 bg-info-solid hover:bg-info-solid-hover text-brand-foreground text-xs font-medium rounded-md transition-colors duration-200 cursor-pointer"
          end
        end
      end
    end
  end
end
