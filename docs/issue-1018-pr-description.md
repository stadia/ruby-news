# #1018 PR 설명

## 문제와 변경 후 동작

품질 게이트가 독립 스킬 CLI를 앱 코드로 측정하고, DeepL 번역·기사 상세 및 최근 늘어난 FederationIngest 복잡도가 기준을 넘으면서 정상 변경도 실패했다. `app/skills/`를 Zeitwerk와 동일한 이유로 Flog에서 제외하고, DeepL·기사 상세의 책임을 작은 메서드로 나누며 FederationIngest의 본문 정규화와 부모 속성 조립 중복을 제거했다. 75/55/93/289 임계값과 다른 측정 범위는 유지했다.

2026-09-26의 교착 로그에는 fixtures를 다시 적재하는 세션과 별도 테스트 프로세스의 쓰기가 충돌했다. Minitest와 RSpec이 같은 PostgreSQL DB를 공유하면 schema/fixtures 작업 전에 비차단 파일 잠금으로 두 번째 실행을 거절한다. 서로 다른 DB는 동시에 실행할 수 있으며 종료 시 잠금이 해제된다. 거절된 실행은 기존 커버리지 결과와 품질 스냅샷을 보존한다. 적용 범위와 사용법은 [테스트 DB 격리](testing-database-isolation.md)에 기록했다.

CI `test` 잡에서 RSpec과 Minitest 뒤에 `bin/rake quality`를 실행해 게이트 실패가 잡 실패로 드러나게 했다. AGENTS.md는 임계값의 기준을 설정 파일로 통일하고 오래된 baseline을 제거했다.

## 전후 품질 게이트

| 지표 | 수정 전 스냅샷·측정 | 수정 후 전체 재측정 | 기준 |
|---|---:|---:|---:|
| Line coverage | 76.35% | 78.25% | >=75% |
| Branch coverage | 58.34% | 60.25% | >=55% |
| Flog method max | 222.77 | 79.69 | <=93 |
| Flog class max | 667.79 | 287.75 | <=289 |

최종 `bin/rake quality`: `4/4 gates passed.`, exit 0. 커버리지는 두 스위트를 새로 실행한 병합 스냅샷 기준이다.

## 검증

- PostgreSQL 18.4 전용 DB에서 RSpec → Minitest: 70 examples, 1,433 runs/5,886 assertions, 실패·오류·skip 0.
- LikesControllerTest 5개 seed 반복: 각 7 runs/35 assertions, 실패·오류 0, 교착 없음.
- Flog 제외 범위: 수정 전 2 failures → 수정 후 4 runs/12 assertions 통과.
- 리팩터링 전후 DeepL 10개/44 assertions, ArticlesController 30개/212 assertions, FederationIngest 91개/312 assertions 통과.
- 실제 프로세스 잠금 테스트: 7 runs/44 assertions. 실제 Rails/RSpec 중복 시작 거절과 coverage 3개 파일 보존도 확인.
- 전체 RuboCop 444개 파일과 마지막 guard 변경 4개 파일, Sorbet, Packwerk 통과. 독립 리뷰에서 결함 없음.
- `graphify update .` 완료, `git diff --check` 통과. 시스템 브라우저 테스트는 화면 변경이 없어 실행하지 않았다.

Gemfile/Gemfile.lock 및 DB 스키마 변경은 없다. 로컬 검증과 코드 변경은 완료했으며, GitHub CI 실행과 main 반영은 PR 생성·머지 후 확인한다.

Closes #1018
