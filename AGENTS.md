# AGENTS.md

AI 에이전트를 위한 프로젝트 룰북입니다.

## 절대 규칙

- 모든 응답은 한국어로 작성하고, 로그와 명령어 출력은 원문 그대로 유지한다.
- 코드 변경 전후의 맥락과 테스트 결과를 커밋 메시지 또는 PR 설명에 기록한다.
- 테스트와 검증은 PostgreSQL 기준으로 수행하며, 필요하면 `TEST_DATABASE_URL`을 우선 사용한다.
- PostgreSQL 확장이 필요한 이 프로젝트를 SQLite 기준으로 해석하거나 검증하지 않는다.
- 인증은 Devise 젬 기반. `current_user` 헬퍼 사용 (not `Current.user`). 모듈: database_authenticatable, registerable, recoverable, validatable, rememberable. 커스텀 컨트롤러(`app/controllers/users/`)에서 Phlex 뷰 렌더링.
- `Article`의 AI 요약, embedding, soft-delete(`discarded_at`), `social_post_ids` JSONB 구조를 무시하고 수정하지 않는다.
- 댓글 기능 수정 시 `awesome_nested_set` 구조와 `Comment::MAX_DEPTH` 제한을 깨뜨리지 않는다.
- Tailwind v4에서 이름이 바뀐 유틸리티는 v4 명칭을 사용한다 (예: `break-words` → `wrap-break-word`).
- Tailwind CSS 색상 클래스는 직접 쓰지 않고, 항상 시맨틱 토큰을 사용한다.
- 기본 locale은 한국어로 유지하고, 새 번역 키는 `config/locales/ko.yml`에 추가한다.
- 날짜와 시간 표시는 `l(Time.current, format: :short)` 규칙을 따른다.
- PostgreSQL 확장, 한국어 요약, 로컬라이제이션 등 운영 환경 전제를 무시한 채 production과 다른 방향으로 구현하지 않는다.
- 뷰와 컴포넌트는 Phlex 기반으로 작성하며, ERB 템플릿을 새로 만들지 않는다.
- UI 요소는 RubyUI 컴포넌트(`RubyUI::Card`, `RubyUI::Avatar`, `RubyUI::DropdownMenu`, `RubyUI::Popover`, `RubyUI::Switch`, `RubyUI::Checkbox` 등)를 우선 사용하고, 해당하는 컴포넌트가 없을 때만 직접 마크업한다.
- UI를 구현할 때 필요한 컴포넌트가 있으면 먼저 `app/components/ruby_ui` 아래 기존 RubyUI 컴포넌트를 찾고, 없을 때만 새로 만든다.
- RubyUI 컴포넌트 수정은 프로젝트 전반에 영향을 주는 공통 규칙 변경이 꼭 필요한 경우에만 한다. 화면 단위 요구사항은 호출부의 class 조정이나 별도 앱 컴포넌트로 해결하는 것을 우선한다.
- 보조 액션 묶음은 `RubyUI::DropdownMenu` 또는 `RubyUI::Popover`를 우선 검토하고, 설정형 on/off 값은 `RubyUI::Switch`, 다중 선택과 동의/필터 항목은 `RubyUI::Checkbox`를 우선 사용한다.
- 아이콘은 PhlexIcons의 Hero 아이콘(`Hero::IconName`)을 우선 사용한다. 브랜드 로고(Google, Apple, GitHub 등)처럼 Hero 아이콘에 해당하지 않는 경우에는 공식 가이드라인을 따르는 SVG를 직접 사용할 수 있다.
- 디자인 및 UI 작업은 `DESIGN.md`의 지침(시맨틱 토큰, 컴포넌트 규칙, 색상 전략, 접근성 기준 등)을 따른다.

## 권장 규칙

- 변경 작업 전 `Article`, `Site`, `User`, `Comment`의 역할과 제약을 먼저 확인하고 영향 범위를 검토한다.
- Ruby 코드에 타입 힌트를 추가하거나 수정할 때는 inline RBS 스타일을 사용한다.
- RED, GREEN 테스트주도개발 방법에 따라 구현 코드보다 먼저 테스트 코드를 작성한 후 구현 코드를 작성한다.
- 서비스 객체를 만들거나 수정할 때는 기존 `OperationService` 을 상속하여 ROP 패턴을 따른다. 단순한 유틸리티성 서비스는 `class << self` 를 사용한 함수 모듈로 작성한다.
- 소셜 미디어 연동 코드는 `SocialMediaService` 기반 구조와 플랫폼별 서비스 분리를 유지한다.
- 변경을 마무리하기 전에 테스트 여부와 미실행 사유를 명확히 남긴다.
- **젬을 올리면(`bundle update`, `bundle add`, Gemfile 수정) 같은 커밋에서 `bin/tapioca gem`을 돌린다.** `srb tc`는 `sorbet/rbi/gems`의 파일을 그대로 읽을 뿐 Gemfile.lock과 맞는지 묻지 않아, RBI 드리프트는 로컬에서 전혀 보이지 않다가 CI의 `tapioca gem --verify`에서 터진다. `Gemfile.lock`이 스테이징되면 lefthook의 `tapioca-gem-drift` 훅이 이를 검사한다(검증만 하고 재생성은 하지 않는다).
- **`bin/tapioca gem`을 돌린 뒤에는 `ruby script/patch_generated_gem_rbis.rb`를 이어서 돌린다.** tapioca는 Ruby 3.2+ 익명 파라미터 포워딩(`def m(*)`, `(**, &)`)에서 `Method#parameters`가 이름을 주지 않아 타입이 빈 sig(`params(_arg1: , _arg2: )`)를 생성하고, `srb tc`가 이를 "Malformed type declaration"으로 거부한다. 이는 tapioca의 한계이지 젬의 결함이 아니므로 **젬 소스를 관용구 이전으로 되돌려 우회하지 않는다.** 도구의 한계는 소비하는 쪽인 이 앱의 RBI 레이어에서 흡수한다. `tapioca gem --verify`는 파일 집합만 검사하므로 이 후처리는 CI를 깨지 않는다. upstream 수정은 [Shopify/tapioca#2687](https://github.com/Shopify/tapioca/pull/2687)(APPROVED, 머지 대기)이며, **이 PR이 머지된 뒤 첫 릴리스에서 스크립트를 통째로 지운다**(최신 v0.19.2가 PR보다 앞서므로 v0.19.3 또는 v0.20.0이 후보). 젬을 올릴 때 스크립트가 "보정할 항목 없음"을 내면 회수 시점이다.
- 관련 배경 문서가 필요하면 `docs/CLAUDE_WORKFLOW.md`, `docs/postgresql-extensions.md`를 우선 참고한다.
- 뷰 클래스는 `Views::Base`를, 컴포넌트 클래스는 `Components::Base`를 상속한다.
- `OperationService`(`Dry::Operation`)의 `call` 메서드에서 `return Failure(:x)`를 직접 반환하면 `Dry::Operation`이 이를 `Success(Failure(:x))`로 감싸버린다. `Failure`를 반환하려면 반드시 `step`을 통해야 한다. guard clause도 `step validate_something(...)` 형태로 호출한다.
- **`class` 대신 `module` 우선 원칙** (ref: Dave Thomas, "Eliminating the `class` Keyword from Ruby"):
  - **오브젝트 팩토리가 아니면 module이다.** 인스턴스 변수, 인스턴스 메서드, 생성자가 없다면 `class`가 아니라 `module`(+ `class << self`)로 작성한다. 함수 모듈의 self 스타일은 `class << self` 로 통일한다(`module_function`·`extend self`는 쓰지 않는다).
  - **추상 기반 클래스(abstract base class)는 Ruby에 필요 없다.** 상속으로 메서드를 주입하는 대신 mixin(`include`/`extend`/`prepend`)을 사용한다. (Rails 프레임워크의 `ApplicationRecord`, `ApplicationController` 등은 예외)
  - **`new` 직후 invalid한 상태면 안 된다.** 생성자에서 모든 필수 값을 받아 유효한 객체만 만들어야 한다. `new` 후 setter 호출이 필요하다면 클래스 설계가 잘못된 것이다.
  - **함수 모듈(`class << self`)의 위치는 `app/functions/`다.** `app/services/`는 상태를 가진 서비스 객체, `OperationService` 상속 객체, 또는 인스턴스 기반 협력 객체에만 사용한다. 단순 함수성 모듈을 습관적으로 `services`·`models` 아래 두지 않는다.
  - **함수 모듈 이름에 불필요한 `_service` postfix를 붙이지 않는다.** 함수 모듈은 `RegistrationService`, `CallbackService`보다 `Registration`, `Callbacks`, `UserMatcher`처럼 역할이 바로 드러나는 이름을 사용한다.
  - **함수 모듈의 진입점 이름을 무조건 `call`로 짓지 않는다.** `call`은 서비스 객체 관용구에 가깝다. `app/functions/` 아래의 함수 모듈은 `match_user`, `suggest_username`, `build_auth_result`, `register_user`처럼 도메인 의미가 드러나는 메서드명을 우선 사용한다.
- **여러 값을 묶어 반환·전달할 때는 untyped Hash 대신 불변 값 객체(`Data.define`)를 쓴다.**
  - `{ success: ..., user: ... }`처럼 결과를 Hash로 반환하지 않는다. `Result = Data.define(:success, :user)`로 정의해 오타 시 `nil` 대신 `NoMethodError`가 나도록 하고, 불변성·값 동등성을 확보한다.
  - bool 필드는 `success?`처럼 술어 메서드를 블록으로 함께 정의해 호출부에서 `result.success?`로 읽히게 한다.
  - 가변 상태가 필요 없는 데이터 묶음에는 `Struct`보다 `Data`(불변)를 우선한다. Success/Failure 모나드는 도입하지 않는다(실패는 가드절·예외로 처리).
  - **`Data.define`에는 심볼만 넘기고, 멤버 타입은 `sorbet/rbi/shims/data_definitions.rbi`에 쓴다.** 인자 줄에 `#:` 주석을 달지 않는다.
    - 이유: rbs-inline과 Sorbet이 같은 `#:` 문법을 다르게 읽는다. rbs-inline은 `Data.define(:path, #: String)`을 멤버 타입 선언으로 읽지만, Sorbet은 `--enable-experimental-rbs-comments` 아래에서 줄 끝 `#:`를 "그 줄 표현식에 대한 타입 단언"으로 읽어 `:path` **심볼**이 `String`이라는 단언으로 해석한다. 단언 실패 → 인자 타입 불일치 → 상수가 클래스로 해석되지 않음(`Constant Entry is not a class or type alias`)까지 연쇄된다.
    - 이 오류는 sorbet-runtime과 무관하다. `T.must`/`T.let` 없이 표기만 바꿔서 제거된다.
    - **`Data.define(...) do ... end` 블록 안에 타입 주석을 넣는 우회는 쓰지 않는다.** rbs-inline은 블록 내부를 파싱하지 않아(`Style/RbsInline/DataDefineWithBlock` cop 메시지) `@rbs`든 `@rbs!`든 생성 RBS는 `untyped`가 되고, Sorbet도 블록 주석을 읽지 않는다. cop만 4종 더 꺼야 하고 얻는 것이 없다.
    - **감수한 대가**: 타입이 살아 있는 RBS를 만드는 표기는 인자 줄 `#:` 하나뿐이므로, 이 규칙 아래에서 rbs-inline 생성물은 멤버가 `untyped`가 된다. 현재 `sig/` 생성과 `rbs collection`은 2026-08-05에 제거됐고(#906) `#:`의 유일한 소비자가 Sorbet이라 실질 손해가 없다. **RBS 생성을 되살린다면 이 규칙을 재검토해야 한다.**
    - 위 표기를 강제하기 위해 `Style/RbsInline/MissingDataClassAnnotation` cop은 `.rubocop.yml`에서 끈다(이 cop이 요구하는 표기가 곧 Sorbet을 깨뜨리는 표기다). 나머지 `Style/RbsInline/*`는 켜 둔다.

## Phlex 컴포넌트·스타일링 규칙

- 화면은 기존 컴포넌트를 조합해 만든다. 같은 패턴의 컴포넌트가 있으면 raw HTML/Tailwind로 다시 짜지 않는다.
- 맞는 컴포넌트가 없는 반복 패턴은 페이지에 인라인으로 짜지 않고, 먼저 `Components::Base`를 상속한 컴포넌트로 만든 뒤 사용한다.
- 컴포넌트가 `variant`/`size` 같은 prop을 제공하면 raw class 대신 prop으로 스타일을 지정한다 (예: `RubyUI::Button(variant: :primary, size: :lg)`, not `class: "bg-..."`).
- 컴포넌트 네임스페이스를 생략하지 않는다 (`RubyUI::Button`, not `Button`).
- Phlex 컴포넌트에 인라인 `style=""` 속성을 넣지 않는다.
- 스타일시트를 새로 만들지 않는다. 새 색상·토큰이 필요하면 `app/assets/tailwind/tokens.css`에 시맨틱 토큰으로 추가하고, 일회성 클래스로 해결하지 않는다.
- 다크 모드 등 테마 전환은 컴포넌트별 오버라이드가 아니라 루트 요소의 `theme-dark` 클래스(`dark:` variant)로 처리한다.

## 도구 사용 규칙

- 라이브러리나 런타임 구조를 조사할 때는 가능한 경우 MCP 서버나 CLI 같은 제공 도구를 목적에 맞게 사용한다.
- 제공된 도구가 더 적합한 작업인데 무조건 파일 전체를 읽거나 비효율적인 방식만 고집하지 않는다.
- 최신 라이브러리 문서나 예제가 필요하면 Context7을 사용하고, `resolve-library-id` 후 `query-docs` 순서로 진행한다.
- 복잡한 문제를 단계적으로 풀어야 할 때는 Sequential Thinking을 사용한다.
- Ruby 코드의 정의 탐색, 참조 찾기, 심볼 검색 등에는 ruby-lsp를 적극 활용한다.

## 외부 프로젝트 경로

- **fedipub**: `../federails` — 젬 이름은 fedipub으로 바뀌었지만 저장소 디렉터리 이름은 `federails` 그대로다. fedipub 관련 코드 조회·수정 시 반드시 이 로컬 경로를 사용한다. 번들러 캐시(`~/.local/share/mise/.../bundler/gems/fedipub-*`)는 읽지 않는다.
- fedipub 수정이 필요하거나 원인이 fedipub에 있다고 판단되면, 앱에서 임시 우회 패치를 넣기 전에 반드시 `../federails`를 직접 확인하고 그 저장소에서 우선 수정한다.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Test Profiling (TestProf)

테스트가 느릴 때 원인을 찾는 계측 도구. **전부 ENV 변수로만 켜지며, 변수 없이 실행하면 아무 영향이 없다.** minitest / RSpec 양쪽에 붙어 있고, `bin/rails test`와 `bundle exec rspec` 모두 아래 변수를 그대로 받는다.

### 어디에 시간이 쓰이는가 (EventProf)
```sh
EVENT_PROF=sql.active_record bin/rails test          # 그룹별 SQL 시간 순위
EVENT_PROF=sql.active_record EVENT_PROF_EXAMPLES=1 bundle exec rspec   # 테스트 단위까지
```
`sql.active_record` 외에 `ActiveSupport::Notifications` 이벤트라면 무엇이든 쓸 수 있다(`render_template.action_view`, `process_action.action_controller` 등). `EVENT_PROF_RANK=count`로 시간 대신 호출 수 기준 정렬, `EVENT_PROF_TOP=N`으로 표시 개수 조정.

### 어떤 종류의 테스트가 느린가 (TagProf)
```sh
TAG_PROF=type bundle exec rspec
```

### 어떤 코드가 느린가 (Vernier — 플레임그래프)
```sh
TEST_VERNIER=1 bin/rails test
```
`tmp/test_prof/vernier-report-wall-total.json`이 생성된다. https://profiler.firefox.com 에 올려서 본다.
`TEST_VERNIER=boot`으로 부팅 구간만, `TEST_VERNIER_MODE=retained`로 메모리 프로파일링.

### 그 외
- `TEST_MEM_PROF=alloc bin/rails test` — 메모리 할당 상위 테스트 (모드는 `alloc`/`rss`/`gc` 셋뿐이고, 그 밖의 값은 에러 없이 `rss`로 폴백한다)
- `SAMPLE=100 bin/rails test` — 전체에서 100개만 무작위 샘플 실행

### CI에서 보기
`profile` 잡이 **main push마다** 두 스위트를 프로파일한다. `continue-on-error`라 계측이 깨져도 머지를 막지 않는다(테스트 통과 여부는 `test` 잡이 판정한다).

PR에서는 돌지 않는다. 계측 고유 비용은 15초 남짓이지만 별도 잡이라 셋업이 통째로 중복돼 PR 파이프라인 벽시계가 2분에서 3분으로 늘어났다. 특정 PR을 프로파일하려면 로컬에서 위 명령을 직접 돌린다.

- **표**: Actions 실행 요약 화면에 EventProf·TagProf 결과가 바로 뜬다. `bin/test-profile-summary`가 로그에서 리포트 블록만 뽑아 `$GITHUB_STEP_SUMMARY`에 쓴다.
- **플레임그래프**: `test-profile` 아티팩트(보존 7일)를 내려받아 Vernier JSON을 https://profiler.firefox.com 에 올린다. 두 러너의 산출물은 `TEST_PROF_REPORT` 접미사로 갈라져 있다(`...-minitest.json`, `...-rspec.json`).

로그 파싱이 필요한 이유: TestProf는 Vernier를 뺀 리포트를 파일로 내보내지 않고 리포터가 표준출력에 직접 찍는다.

### 주의
- 이 프로젝트는 fixtures 기반이므로 FactoryProf / FactoryDoctor는 해당 없음.
- minitest 6.0이 젬 플러그인 자동 탐색을 없앴으므로 `test/test_helper.rb`가 `Minitest.load "test_prof"`로 명시 등록한다. 이 줄을 지우면 minitest 쪽 EventProf/TagProf가 조용히 동작하지 않는다.
- 산출물은 `tmp/test_prof/`에 쌓이며 `.gitignore`의 `/tmp/*`가 이미 덮는다.

## Quality Gates

This project uses automated quality gates. **Run `bin/rake quality` before declaring any task complete.** Do not commit if any gate fails. Report the gate numbers in your response so regressions are visible.

### Gates
- **Line coverage** >= 70.0% (SimpleCov)
- **Branch coverage** >= 50.0% (SimpleCov)
- **Flog max (method)** <= 93 (app code only; views/components excluded)
- **Flog max (class)** <= 289 (app code only; views/components excluded)

### Thresholds
Thresholds live in `config/quality_thresholds.yml`.

### Coverage snapshot note
- `bin/rake quality` reads coverage from `coverage/.quality_last_run.json` first.
- `bin/rails test` (full suite) refreshes that snapshot.
- Partial test runs only update `coverage/.last_run.json`, so they do not lower the quality gate coverage baseline.
- If coverage looks stale, run `bin/rails test` once before `bin/rake quality`.

### Current Baseline (as of setup)
- Line Coverage: ~43% (needs improvement to reach 60%)
- Branch Coverage: ~51% (needs improvement to reach 50%)
- Flog method max: ~373 (needs refactoring to reach 20)
- Flog class max: ~406 (needs refactoring to reach 70)
