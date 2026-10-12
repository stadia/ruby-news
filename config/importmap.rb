# Pin npm packages by running ./bin/importmap
# rbs_inline: enabled

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# 컨트롤러는 lazyLoadControllersFrom로 지연 로드하므로 preload하지 않는다.
# (preload하면 모든 컨트롤러 파일이 즉시 다운로드되고, modulepreload가
#  chart.js 같은 무거운 의존성까지 재귀적으로 끌어올 수 있다.)
pin_all_from "app/javascript/controllers", under: "controllers", preload: false
# 단, 진입 모듈(index·application·page_loader_controller)은 Components::Layout의
# CONTROLLER_ENTRY_MODULES에서 따로 modulepreload한다. pin_all_from은 같은 이름의 개별 pin을
# 디렉터리의 preload 값으로 덮어써서, 개별 pin으로는 켤 수 없다.

# utils(form_helpers)의 소비자(post_form/reply_form 컨트롤러)가 모두 lazy이므로
# 함께 preload에서 제외한다.
pin_all_from "app/javascript/utils", under: "utils", preload: false
# 아래 라이브러리들은 lazy 로드되는 Stimulus 컨트롤러에서만
# 쓰인다. importmap-rails의 pin 기본값은 preload: true라서, 그대로 두면
# <link rel="modulepreload">로 전 페이지에서 즉시 다운로드된다. preload: false로
# 명시해 실제로 필요한 페이지에서 동적 import될 때만 fetch되게 한다.
pin "@floating-ui/dom", to: "@floating-ui--dom.js", preload: false # @1.7.6
pin "@floating-ui/core", to: "@floating-ui--core.js", preload: false # @1.7.5
pin "@floating-ui/utils", to: "@floating-ui--utils.js", preload: false # @0.2.11
pin "@floating-ui/utils/dom", to: "@floating-ui--utils--dom.js", preload: false # @0.2.11
pin "embla-carousel", preload: false # @8.6.0
pin "lexxy", to: "lexxy.min.js"
# reactionview 젬이 preload: true로 pin하지만 앱 JS는 import하지 않는다.
pin "reactionview", to: "reactionview.esm.js", preload: false
pin "@rails/activestorage", to: "activestorage.esm.js"
pin "chart.js", preload: false # @4.5.1
pin "@kurkle/color", to: "@kurkle--color.js", preload: false # @0.3.4
pin "@stimulus-components/lightbox", to: "@stimulus-components--lightbox.js", preload: false # @4.0.0
pin "lightgallery", preload: false # @2.9.0
pin "@stimulus-components/character-counter", to: "@stimulus-components--character-counter.js", preload: false # @5.1.0
