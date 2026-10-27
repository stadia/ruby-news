---
id: ruby-news-architecture
type: architecture-design
status: active
title: Ruby-News 시스템 구조
parent: ruby-news-goals
references: [ruby-news-layers, ruby-news-design, ruby-news-domain, ruby-news-jobs, ruby-news-processing, ruby-news-clients, ruby-news-discovery, ruby-news-oauth]
---

# 시스템 구조

## 실행 구조

Ruby 4 / Rails 8.1 단일 애플리케이션이다. HTTP 화면은 Phlex·RubyUI·Turbo/Stimulus, JSON API는 `/api/v1`, 연합 프로토콜은 마운트된 Fedipub 엔진을 통해 제공한다. 관리자와 작업 대시보드는 권한 있는 운영 진입점이다.

주 데이터는 PostgreSQL의 `ra_news` 스키마에 둔다. 전문 검색과 pgvector를 사용하므로 SQLite로 주 데이터 검증을 대체하지 않는다. `config/database.yml`의 Solid Cache/Queue/Cable용 SQLite 보조 저장소는 주 데이터와 다른 역할이다. 이 분리의 운영상 선택 이유는 미확인이다.

## 흐름과 의존 경계

수집 잡 → Site별 외부 client → Article 저장 → 기사 처리 서비스 → AI/외부 도구 → 요약·임베딩 저장이 뉴스 생성 경로다. 화면과 API의 탐색은 기사 질의 함수를 통해 모델을 조회한다. 게시·답글은 Post에, 연합 송수신은 Article/Post/User와 Fedipub의 협력에 걸쳐 있다.

- `ruby-news-jobs`는 작업 실행과 예약을, `ruby-news-processing`은 처리 순서와 실패 정책을 소유한다. 둘은 `ruby-news-domain`과 외부 연동을 사용한다.
- `ruby-news-discovery`는 모델 질의 및 검색용 RubyLLM 임베딩 호출을 사용한다. 모든 외부 호출이 client 계층에 격리되어 있다고 가정하지 않는다.
- 인증 presentation → `ruby-news-oauth` → 모델·GitHub client가 OAuth 경로다. HTTP 세션 변경은 controller 책임이다.
- `ruby-news-clients`는 외부 통신 세부를 맡는다. 도메인 객체 조합과 유스케이스는 호출자 책임이다.
- 화면과 컴포넌트의 공통 계약은 `ruby-news-design`, 실제 정적 계층 검사 범위는 `ruby-news-layers`가 소유한다. 디렉터리 전체가 이미 계층화되었다고 해석하지 않는다.

위 경계는 코드 분석을 바탕으로 작성했으며 사용자 검토와 승인을 거쳤다. 형제 모듈 간 의존 설명은 이 문서에 모으고, 각 모듈은 자기 책임과 계약만 기술한다.

## 구현상의 제약

상태 없는 함수 모듈은 `app/functions`, 인스턴스 기반 협력 객체와 OperationService는 `app/services`에 둔다. 서비스의 ROP 실패는 `step`을 통해 전파해야 하며 `call`에서 직접 반환한 Failure를 정상 결과처럼 감싸지 않도록 한다. 기존 `SocialMediaService` 상속 구조는 유지한다.

테스트는 `TEST_DATABASE_URL`을 우선한 PostgreSQL 기준이다. 품질 판정은 `bin/rake quality`와 `config/quality_thresholds.yml`을 기준으로 하며, 부분 테스트의 커버리지는 전체 스냅샷을 대체하지 않는다.

## 근거와 문서 차이

근거는 AGENTS.md, README.md, routes/database 설정, 모델·잡·서비스·질의 함수다. README는 입력 자료이지 별도 스펙 노드가 아니다. README의 임베딩 1536차원 및 별도 Comment 설명은 현재 코드와 다르므로 `ruby-news-domain`의 현 구현 계약을 따른다. AGENTS.md의 `Comment::MAX_DEPTH`는 현 모델에서 확인되지 않아 실재하는 제한으로 옮기지 않았다. 이번 작업에서는 기존 룰북과 README를 수정하지 않는다.
