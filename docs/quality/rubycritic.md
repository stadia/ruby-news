# RubyCritic: 복잡도 × 변경 빈도 추적

`bin/rake quality`의 Flog·커버리지 게이트를 대체하지 않는다. 게이트는 "넘으면 안 되는 선"이고, 이 리포트는 "어디부터 볼지"를 정하는 참고 자료다(#1015).

## 실행

```sh
bin/rubycritic                                    # churn: 최근 6개월
RUBYCRITIC_CHURN_AFTER=2026-04-11 bin/rubycritic  # 기준선과 같은 기간으로 재현
```

- 범위: `app/models app/controllers app/services app/functions app/clients`(`bin/rubycritic`에 고정)
- 산출물: `tmp/rubycritic/overview.html`, `tmp/rubycritic/report.json`(`/tmp/*`라 Git에 안 들어간다)
- stdout에는 요약 마크다운(`lib/quality/rubycritic_report.rb`)을 찍는다. 분석이 실패하면 0이 아닌 코드로 끝난다.
- **앱 번들과 분리**: `tools/rubycritic/Gemfile`로 돈다. RubyCritic은 reek·virtus·dry-types 등 15개 젬을 끌어오는데, 앱 Gemfile에 넣으면 앱의 `Gemfile.lock`·gem RBI(`tapioca gem --verify`)·배포 이미지까지 바뀐다. 분리해 두면 앱 실행과 타입 검사에 영향이 없다. 처음 실행할 때 `BUNDLE_GEMFILE=tools/rubycritic/Gemfile bundle install`이 필요하다.
- Rails를 부팅하지 않는다. DB도 필요 없다.

## 변경 빈도(churn) 산정

- RubyCritic 내장 churn을 쓴다: `--churn-after DATE` 이후 **해당 파일을 건드린 커밋 수**(`git log`).
- 기간은 실행일 기준 **최근 6개월**. 전체 이력을 쓰면 초기 대량 커밋(생성기 출력, 초기 마이그레이션)에 끌려간다.
- main은 squash 머지라 커밋 수 ≈ 그 파일을 바꾼 PR 수다.
- **우선순위 = churn × complexity(Flog 총점)**. 자주 바뀌지만 단순한 파일, 복잡하지만 거의 안 바뀌는 파일보다 둘 다 높은 파일을 먼저 본다.
- 한계
  - 기계적인 일괄 커밋(Sorbet 시길 부여, fedipub 리네임 등)도 1회로 센다. 상위 파일은 실제 이력을 보고 판단한다.
  - 파일을 옮기면 churn이 새 경로에서 0부터 다시 쌓인다.
  - CI에서는 얕은 클론이면 churn이 전부 1이 된다. 전체 이력(`fetch-depth: 0`)이 필요하다.
- RubyCritic 총점·등급은 참고용이다. **점수만 올리려는 일괄 수정은 하지 않는다.**

## 기준선 (2026-10-11)

`RUBYCRITIC_CHURN_AFTER=2026-04-11 bin/rubycritic`, RubyCritic 5.0.0, main `2daff9dc` 이후.

| 항목 | 값 |
|---|---|
| 총점 | 79.3 |
| 분석 파일 | 138 |
| 등급 | A 66 / B 22 / C 34 / D 16 / F 0 |

`docs/audits/2026-07-10-rails-audit-report.md`의 81.1점은 범위와 버전이 달라 비교하지 않는다(과거 참고값).

| # | 파일 | churn × 복잡도 | churn | 복잡도 | 등급 | 비용 |
|---|---|---|---|---|---|---|
| 1 | `app/controllers/articles_controller.rb` | 9108 | 33 | 276 | D | 11.0 |
| 2 | `app/models/article.rb` | 6905 | 42 | 164 | C | 6.6 |
| 3 | `app/services/article_agents_service.rb` | 6331 | 38 | 167 | D | 8.7 |
| 4 | `app/controllers/home_controller.rb` | 4665 | 23 | 203 | D | 9.1 |
| 5 | `app/models/post.rb` | 4317 | 25 | 173 | C | 6.9 |
| 6 | `app/controllers/posts_controller.rb` | 3650 | 14 | 261 | D | 10.4 |
| 7 | `app/functions/sitemap_builder.rb` | 3402 | 26 | 131 | C | 5.2 |
| 8 | `app/models/concerns/posts/federation_ingest.rb` | 3165 | 11 | 288 | D | 11.5 |
| 9 | `app/clients/discord_client.rb` | 2488 | 11 | 226 | D | 12.0 |
| 10 | `app/functions/oauth_accounts/callbacks.rb` | 2311 | 11 | 210 | D | 8.4 |

### 상위 후보 메모

이력(`git log --since=2026-04-11 -- <파일>`)과 구조를 보고 남긴 첫 판단이다. 리팩터링 결정이 아니라 다음에 볼 지점이다.

1. **`ArticlesController`** — 검색(하이브리드·제안어), SEO/GEO 구조화 데이터(`build_news_article`, `article_speakable`), 기사 등록(메타데이터 준비·자동 좋아요·레이트 리밋), 사이드바(태그·좋아요·부스트 id)가 한 컨트롤러에 있다. 검색 개선·SEO·등록 정책이 각자 이 파일을 고친다. 검색 화면 조합은 #843에서 한 번 분리했다. 다음 후보는 구조화 데이터 조립이다.
2. **`Article`** — churn의 상당수가 Sorbet 시길·nil 가드·fedipub 리네임 같은 일괄 커밋이다. 실질 변경은 일본어 번역 스코프(`missing_japanese`·`needs_japanese`), 썸네일 CDN, IndexNow 콜백 쪽이다. 검색·연합·번역·썸네일 책임이 모델에 모여 있고 MODEL-01에서 일부를 뺐다. 일괄 커밋을 빼고 다시 보면 순위가 내려갈 수 있다.
3. **`ArticleAgentsService`** — LLM 파이프라인(본문 확보·임베딩·요약·윤문·썸네일·일본어·무관 기사 정리)의 조율자라, 모델·프롬프트·실패 정책이 바뀔 때마다 고친다. 단계별 실패 정책(어느 단계는 계속, 어느 단계는 폐기)이 메서드 안에 흩어져 있는 점이 복잡도의 원인이다. DESIGN-02에서 프롬프트·응답 파싱은 분리했다.
4. **`HomeController`** — 홈 화면 조합(추천·최근·사이드바)에 더해 `rss`·`llms`·`robots`·정적 문서 3종·`publisher_schema`까지 맡는다. SEO와 피드 변경이 홈 화면과 같은 파일을 고친다. 피드·크롤러용 액션 분리가 후보다.
5. **`Post`** — 짧은 글·댓글·블로그(장문)가 한 모델이고 연합 수신·발신 concern이 붙어 있다. 블로그 기능 추가(slug, 휴지통, 반응)가 이 파일에 몰렸다. 블로그 전용 규칙이 `Posts::Blog`로 더 옮겨 갈 수 있는지 본다.

## 다음 실행 때

같은 기간 정의(실행일 기준 6개월)로 돌려 위 표와 비교한다. 순위가 크게 바뀌면 이유(리팩터링, 일괄 커밋 이탈)를 이 문서에 덧붙인다.
