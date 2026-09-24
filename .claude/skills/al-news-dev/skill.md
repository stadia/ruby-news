---
name: al-news-dev
description: "AlNews 프로젝트에서 기능 개발, 버그 수정, 리팩토링 등 코드 변경이 필요한 모든 개발 작업을 수행하는 오케스트레이터. '기능 추가해줘', '구현해줘', '만들어줘', '수정해줘', '버그 수정', '에러 해결', '리팩토링', '컴포넌트 추가', '페이지 만들어줘', '모델 추가', 'API 추가' 등 코드 변경을 동반하는 작업을 요청하면 반드시 이 스킬을 사용할 것. 단순 질문이나 설명 요청에는 트리거하지 않는다."
---

# AlNews Development Orchestrator

AlNews 프로젝트의 개발 작업을 scout → builder → guard 파이프라인으로 수행하는 오케스트레이터.

## 실행 모드: 서브 에이전트

## 에이전트 구성

| 에이전트 | subagent_type | 역할 | 출력 |
|---------|--------------|------|------|
| scout | scout | 컨텍스트 수집 | `_workspace/01_scout_context.md` |
| builder | builder | 코드 구현 | 코드 변경 + `_workspace/02_builder_changes.md` |
| guard | guard | 품질 검증 | `_workspace/03_guard_report.md` |

## 워크플로우

### Phase 1: 준비

1. 사용자 요청을 분석하여 작업 유형을 판단한다:
   - **feature**: 새 기능 추가 (모델/컨트롤러/뷰/서비스 등)
   - **bugfix**: 버그 수정, 에러 해결
   - **refactor**: 기존 코드 리팩토링
   - **ui**: UI/컴포넌트 변경
2. `_workspace/` 디렉토리를 생성한다

### Phase 2: 컨텍스트 수집 (Scout)

Scout 에이전트를 실행하여 작업에 필요한 컨텍스트를 수집한다.

```
Agent(
  prompt: "다음 작업을 위한 컨텍스트를 수집하라: {사용자 요청 요약}
  
  작업 유형: {feature|bugfix|refactor|ui}
  
  graphify(query/path/explain)로 관련 모델, 컨트롤러, 뷰, 서비스, 라우트를 조사하라.
  결과를 _workspace/01_scout_context.md에 저장하라.
  
  반드시 포함할 내용:
  - 관련 모델 스키마 및 연관관계
  - 관련 컨트롤러/액션
  - 관련 뷰/컴포넌트 (Phlex 클래스)
  - 참고할 유사 구현 패턴
  - 영향 범위 (함께 수정할 파일)
  - 프로젝트 제약 사항",
  subagent_type: "scout",
  model: "opus"
)
```

Scout 완료 후 `_workspace/01_scout_context.md`를 Read하여 품질을 확인한다. 핵심 정보가 누락되었으면 추가 조회를 직접 수행한다.

### Phase 3: 구현 (Builder)

Builder 에이전트를 실행하여 코드를 구현한다.

```
Agent(
  prompt: "_workspace/01_scout_context.md를 읽고 다음 작업을 구현하라: {사용자 요청 요약}
  
  scout의 컨텍스트를 기반으로 프로젝트 컨벤션에 맞춰 코드를 작성하라.
  변경 사항을 _workspace/02_builder_changes.md에 요약하라.
  
  필수 컨벤션:
  - 뷰: Phlex (Views::Base 상속), ERB 금지
  - 컴포넌트: Components::Base 상속, RubyUI 우선
  - 서비스: OperationService 상속, ROP 패턴
  - i18n: ko.yml에 한국어 번역 추가
  - 아이콘: Hero::IconName
  - Tailwind: 시맨틱 토큰, dark: prefix",
  subagent_type: "builder",
  model: "opus"
)
```

### Phase 4: 검증 (Guard)

Guard 에이전트를 실행하여 변경 사항을 검증한다.

```
Agent(
  prompt: "_workspace/02_builder_changes.md를 읽고 변경 사항을 검증하라.
  
  검증 순서:
  1. bin/rubocop·bundle exec srb tc로 모든 변경 파일 검증
  2. rails test로 테스트 실행
  3. 컨벤션 준수 확인 (Phlex, RubyUI, i18n, Tailwind 등)
  4. 경계면 정합성 확인 (컨트롤러↔뷰, 모델↔스키마)
  
  결과를 _workspace/03_guard_report.md에 저장하라.
  PASS/WARN/FAIL 판정을 포함하라.",
  subagent_type: "guard",
  model: "opus"
)
```

### Phase 5: 결과 처리

Guard 보고서를 읽고 결과에 따라 처리한다:

| 판정 | 처리 |
|------|------|
| **PASS** | 사용자에게 완료 보고 |
| **WARN** | 경고 내용을 사용자에게 안내하고 수정 여부 확인 |
| **FAIL** | guard 보고서의 수정 사항을 builder에게 전달하여 재구현 (최대 2회) |

**재구현 시:**
```
Agent(
  prompt: "_workspace/03_guard_report.md의 FAIL 항목을 수정하라.
  
  수정 사항:
  {guard 보고서에서 추출한 구체적 수정 내용}
  
  수정 후 _workspace/02_builder_changes.md를 업데이트하라.",
  subagent_type: "builder",
  model: "opus"
)
```

재구현 후 guard를 다시 실행한다. 2회 재시도 후에도 FAIL이면 사용자에게 보고하고 수동 개입을 요청한다.

### Phase 6: 정리

1. `_workspace/` 보존 (감사 추적용)
2. 사용자에게 결과 요약:
   - 변경된 파일 목록
   - 주요 변경 내용
   - 테스트 결과
   - 추가 필요 작업 (있으면)

## 데이터 흐름

```
사용자 요청
    ↓
[scout] → _workspace/01_scout_context.md
    ↓
[builder] → 코드 변경 + _workspace/02_builder_changes.md
    ↓
[guard] → _workspace/03_guard_report.md
    ↓
PASS? → 완료 보고
FAIL? → [builder 재실행] → [guard 재실행] (최대 2회)
```

## 에러 핸들링

| 상황 | 전략 |
|------|------|
| scout 실패 | graphify 없이 파일 직접 읽기로 폴백. 최소한 관련 파일 경로라도 수집 |
| builder 실패 | 에러 내용을 분석하고 컨텍스트를 보강하여 1회 재시도 |
| guard 실패 | 부분 검증 결과라도 보고서에 포함. 실행 불가 항목은 SKIP 표시 |
| 2회 재구현 후에도 FAIL | 사용자에게 보고하고 수동 개입 요청 |

## 테스트 시나리오

### 정상 흐름
1. 사용자: "Article 모델에 reading_time 필드를 추가해줘"
2. Phase 2: scout이 Article 모델, 스키마, 관련 뷰를 조사
3. Phase 3: builder가 마이그레이션 + 모델 + 뷰 수정
4. Phase 4: guard가 검증 → PASS
5. Phase 6: 변경 파일 목록과 요약 보고

### 에러 흐름
1. 사용자: "댓글 정렬을 최신순으로 바꿔줘"
2. Phase 2: scout이 Post 모델과 Comments 컴포넌트 조사
3. Phase 3: builder가 스코프 추가 + 뷰 수정
4. Phase 4: guard 검증 → FAIL (테스트 실패)
5. Phase 5: builder 재실행 → guard 재검증 → PASS
6. Phase 6: 완료 보고
