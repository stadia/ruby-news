# typed: true
# frozen_string_literal: true

class Components::Articles::Form < Components::Base
  include Phlex::Rails::Helpers::FormWith
  include Phlex::Rails::Helpers::Pluralize

  attr_reader :article

  def initialize(article:)
    @article = article
  end

  def view_template
     form_with(model: article, class: "contents") do |form|
       if article.errors.any?
         div(id: "error_explanation", class: "bg-danger-solid/10 text-danger-text px-3 py-2 font-medium rounded-md mt-3 border border-danger-solid/30") do
           h2 {
             t("articles.form.errors_heading", count: article.errors.count)
           }
           ul(class: "list-disc ml-6") {
             article.errors.each do |error|
               li { error.full_message }
             end
           }
         end
       end

       render RubyUI::FormField.new(class: "my-5") do
         render RubyUI::FormFieldLabel.new(for: :article_url) { ::Article.human_attribute_name(:url) }
         form.text_field :url, class: [ "block shadow-sm rounded-md border px-3 py-2 mt-2 w-full bg-app text-content placeholder:text-content-muted focus:outline-none focus:ring-2 focus:border-transparent transition-colors duration-200", { "border-input focus:ring-brand": article.errors[:url].none?, "border-danger-text focus:ring-danger-solid": article.errors[:url].any? } ]
         article.errors[:url].each do |msg|
           render RubyUI::FormFieldError.new { msg }
         end
       end

       div(class: "inline") do
         render RubyUI::Button.new(
           type: "submit",
           size: :lg,
           class:
             "w-full sm:w-auto rounded-md bg-brand-solid hover:bg-brand-solid-hover text-brand-foreground inline-block font-medium cursor-pointer focus:outline-none focus:ring-2 focus:ring-brand focus:ring-offset-2 focus:ring-offset-app",
         ) { t("articles.form.submit") }
       end
     end
  end
end
