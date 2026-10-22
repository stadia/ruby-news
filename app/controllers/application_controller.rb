# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

require "schema_dot_org/web_site"

class ApplicationController < ActionController::Base
  include LocaleSwitcher

  # 방문은 article 조회 이벤트가 발생할 때만 생성한다.
  skip_before_action :track_ahoy_visit

  before_action :authenticate_user!
  allow_browser versions: { ie: false }
  # 로컬로 뽑은 건 후행 `#:` 타입 단언이 붙을 대입문이 필요해서다(인라인
  # `layout -> { ... }`에는 postscript 형식을 달 수 없다). `controller` 인자는
  # ActionView가 기대하는 레이아웃 proc arity와 맞춘 것.
  application_layout = ->(controller) { controller.request.format.turbo_stream? ? false : Components::Layout } #: ^(ApplicationController) -> (singleton(Components::Layout) | false)
  layout application_layout

  before_action :set_web_site_schema

  unless Rails.env.production?
    around_action :n_plus_one_detection

    # `around_action` hands the rest of the request cycle in as a block, which
    # nothing in the source declared -- the annotation is what lets the bare
    # `yield` below type check. The `(&)` is required: Sorbet rejects a block
    # in the signature when the `def` has no block parameter (srb.help/3552).
    #: () { () -> void } -> void
    def n_plus_one_detection(&)
      Prosopite.scan
      yield
    ensure
      Prosopite.finish
    end
  end

  private

  def set_web_site_schema
    return unless request.path == "/"

    base = request.base_url
    @web_site = SchemaDotOrg::WebSite.new(
      name: t("layout.site_name"),
      url: base,
      potential_action: SchemaDotOrg::SearchAction.new(
        target: "#{base}/articles?search={search_term_string}",
        query_input: "required name=search_term_string"
      )
    )
  end

  # CSRF 면제는 실제 JSON Content-Type의 쓰기 요청에만 적용해야 한다. Rails는 `if:`와 `only:`를
  # OR로 평가해 HTML POST까지 통째로 면제되므로, 하나의 술어 안에서 AND로
  # 조합해야 한다.
  #: () -> bool
  def skip_csrf_for_json_write?
    json_request? && action_name.in?(%w[create destroy])
  end

  #: () -> bool
  def json_request?
    request.content_mime_type == Mime[:json]
  end

  def cacheable_page!(max_age: 5.minutes)
    return if user_signed_in?
    request.session_options[:skip] = true
    expires_in max_age, public: true
  end
end
