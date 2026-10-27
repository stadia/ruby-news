---
id: ruby-news-discovery
type: module-design
status: active
title: 기사 탐색과 처리 함수
parent: ruby-news-architecture
depends-on: [ruby-news-domain]
---

# 기사 탐색과 처리 함수

코드 분석을 바탕으로 작성했으며 사용자 검토와 승인을 거쳤다. 기사 조회·검색·등록 보조·AI 입력 및 응답 정규화 같은 기사 유스케이스의 함수들을 소유한다. HTTP 세션이나 화면 렌더링을 소유하지 않으며, 상태 없는 진입점은 module의 `class << self` 스타일을 따른다. 전체 협력 구조는 `ruby-news-architecture`에 둔다.

## 검색 계약

HybridSearch는 전문 검색과 벡터 후보 순위를 RRF로 결합한다. 임베딩을 얻지 못하면 전문 검색으로 축소 동작한다. 벡터 후보·임계값·선택적 MMR 재정렬은 cosine 기준을 일치시킨다. 전문 검색에서 찾은 후보를 벡터 임계값만으로 제거하지 않는다.

현재 임베딩 모델은 gemini-embedding-2다. 차원 계약은 `ruby-news-domain`을 따르며 기사 생성과 질의가 같은 모델·차원을 사용해야 한다. 질의 임베딩 캐시는 모델을 키에 포함한다. 검색 파라미터는 config/hybrid_search.yml을 따르고 검색은 kept·confirmed 기사를 후보로 삼는다.

## 경계

이 디렉터리의 일부 함수는 모델 조회 및 RubyLLM 호출을 하므로 모두 순수 함수라고 해석하지 않는다. 기사 파이프라인의 순서와 폐기 결정은 `ruby-news-processing`의 책임이며, 응답 정규화나 프롬프트 생성이 독자적으로 처리 단계를 재배열하지 않는다.
