# #1018 품질 게이트 복구 계획

> 구현: 독립 리팩터링은 병렬 에이전트로 수행하고, PostgreSQL 테스트는 하나씩 실행한다.

**목표:** 임계값을 유지하며 전체 테스트와 4개 품질 게이트를 통과시키고 CI에서 강제한다.
**명세:** https://github.com/stadia/ruby-news/issues/1018
**기술:** Rails, PostgreSQL 18, Minitest/RSpec, Flog, SimpleCov, Sorbet.

## 제약과 검토 항목

- 임계값 75/55/93/289 유지. 앱 런타임 밖의 `app/skills/`만 Flog에서 추가 제외한다.
- DeepL의 ROP 실패, 출력 계약, nil/개수 불일치/쿼터/네트워크 오류 폴백을 유지한다.
- 기사 상세 HTML/Markdown, 호스트 기반 publisher, locale/noindex, 썸네일, embedding을 유지한다.
- DB 잠금/비동기 작업을 관찰하고 재현 근거 없이 앱 동시성 코드를 수정하지 않는다.
- 전체 테스트는 별도 PostgreSQL DB에서 직렬로 실행하며 line 76%, branch 56% 이상을 목표로 한다.

## 작업

### 1. 측정 범위와 실행 환경 (root)
- [x] 현재 quality 실패와 PostgreSQL 버전·활성 세션을 기록한다.
- [x] FlogParser의 app/skills 제외, components/views 제외 유지, 실제 앱 포함을 회귀 테스트한다.
- [x] 테스트 RED 확인 후 경로 필터를 수정한다. 별도 PostgreSQL 테스트 DB를 준비한다.

### 2. DeepL 번역 분해 (deepl_refactor)
- [x] `test/services/deepl_translation_service_test.rb`에 입력 순서와 오류·쿼터 회귀 테스트를 먼저 보강한다.
- [x] 기존 구현에서 테스트를 실행한 뒤 `run_translation`을 작은 메서드로 분해한다.
- [x] 관련 테스트·Flog·RuboCop·Sorbet 결과를 기록한다.

### 3. 기사 상세 분해 (articles_refactor)
- [x] `test/controllers/articles_controller_test.rb` 및 관련 테스트에서 상세 응답과 메타데이터 미커버 분기를 먼저 보강한다.
- [x] 기존 동작을 확인한 뒤 `show`의 메타데이터·유사기사 처리 등을 private 메서드로 분해한다.
- [x] 관련 테스트·Flog·RuboCop·Sorbet 결과를 기록한다.

### 4. 교착 조사 및 전체 검증 (root)
- [x] LikesControllerTest 단독 반복 실행과 전체 테스트 중 PostgreSQL 세션·잠금을 관찰한다.
- [x] 재현 시 원인을 먼저 규명하고 회귀 테스트 후 수정한다. 재현되지 않으면 조사 범위와 한계를 기록한다.
- [x] RSpec → 전체 Minitest 순서로 깨끗한 커버리지 병합 결과를 만든다.
- [x] 부족한 커버리지는 관련 동작 테스트로 보강한다.

### 5. CI·문서 및 마무리 (root)
- [x] `.github/workflows/ci.yml` test 잡의 두 스위트 뒤에 차단형 `bin/rake quality`를 추가한다.
- [x] `AGENTS.md`에서 설정 파일을 임계값의 기준으로 삼고 오래된 baseline을 삭제한다.
- [x] `bin/rake quality`, RuboCop, Sorbet, Packwerk, graphify update를 실행한다.
- [x] 변경 설명·전후 측정·테스트 결과를 리뷰 가능한 문서 또는 PR 설명으로 남긴다.

## 실행 기록

- 작업 브랜치는 `fix/issue-1018-quality-gates`다. 최종 변경과 검증 기록을 이 브랜치에 커밋하고 main 대상 PR로 제출한다. 기존 미추적 `.build/`, `docs/handoffs/`는 보존한다.
- PostgreSQL 18.4 확인. 조사 시작 시 테스트 DB에 활성 세션 없음.
- 두 구현 작업은 파일 소유권이 분리되어 있다. DB와 coverage 결과는 root가 실행 순서를 조정한다.

## 완료 기록

- 작업 1~5 완료. 기존 게이트 임계값은 그대로 유지했다.
- 추가 판단: 현재 main의 `Posts::FederationIngest`도 클래스 306.1로 기준을 초과해, 기존 concern에서 중복만 제거했다. 전후 기존 PostgreSQL 회귀 테스트 91개가 통과했고 클래스 점수는 287.75가 됐다.
- 교착 원인: 당시 서버의 fixture 재적재와 별도 테스트 프로세스 쓰기 충돌을 확인했다. 양 러너에 공유 파일 잠금으로 중복 실행을 차단하고, 거절 시 SimpleCov 결과가 기존 스냅샷을 덮지 않도록 했다.
- 전용 DB에서 LikesControllerTest를 seed 1018/2026/42/99/12345로 실행: 각 7개, 실패 0.
- 전체 RSpec 70개, 전체 Minitest 1,433개/5,886 assertions: 실패·오류·skip 0, 교착 없음.
- 실제 Minitest/RSpec 중복 시작 거절과 coverage 3개 파일 불변을 통합 검증했다. 독립 잠금 회귀 테스트 7개/44 assertions도 통과했다.
- 최종 quality: line 78.25%, branch 60.25%, method max 79.69, class max 287.75. `4/4 gates passed.`, exit 0.
- 전체 RuboCop 444개 파일, 마지막 guard 변경 4개 파일, Sorbet, Packwerk, graphify update, diff 검사 통과.
- 독립 최종 리뷰: Critical/Important/Minor 결함 없음. 잠금은 같은 사용자·임시 디렉터리를 공유하는 로컬 러너를 보호한다. 다른 머신이나 DB 호스트 별칭까지 동일 잠금으로 통합하지 않는 경계는 격리 문서에 기록했다.
- Gemfile.lock의 일시적인 외부 변경은 최종 diff에 없으며, 이번 작업에 젬 변경은 없다. 기존 미추적 `.build/`, `docs/handoffs/`는 보존했다.
