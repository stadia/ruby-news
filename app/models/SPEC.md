---
id: ruby-news-domain
type: module-design
status: active
title: 콘텐츠와 계정 도메인
parent: ruby-news-architecture
---

# 콘텐츠와 계정 도메인

코드 확인을 바탕으로 작성했으며 사용자 검토와 승인을 거쳤다. 모델은 영속성·검증·연관·공개 가능 상태를 소유한다. 전체 의존 구조와 검사 범위는 `ruby-news-architecture`와 `ruby-news-layers`를 따른다.

## 데이터 계약

- Article은 수집 기사와 AI 산출물의 기준 레코드다. `discarded_at` 기반 soft-delete, `social_post_ids` JSONB, 한국어·일본어 표시 속성을 유지한다. 임베딩은 현재 3072차원이고 검색 모델 및 DB halfvec 컬럼과 함께 변경해야 한다.
- Site는 수집원 유형·접속 설정·마지막 점검 상태를 보유한다. source별 통신 자체는 client와 잡의 책임이다.
- User는 Devise 인증과 로컬 작성자·연합 actor 연결을 소유한다. 현재 사용자 조회는 `current_user`이며 별도 전역 사용자 상태를 도입하지 않는다.
- Post가 단문·블로그·댓글을 통합한다. `awesome_nested_set` 트리의 삭제는 콜백을 거쳐 자식과 카운터·연합 처리를 일치시킨다. 별도 Comment 모델이나 MAX_DEPTH 상수는 현 코드에서 확인되지 않았다.

## 게시와 삭제의 의미

Post의 초안은 로컬 전용이며 공개 발행 전에 연합하지 않는다. 블로그는 삭제함·복원을 지원하고 단문·댓글은 hard-destroy한다. 첫 발행은 원격에서 생성으로 인식되어야 하며, 발행된 블로그의 slug는 제목 편집으로 바꾸지 않는다. 공유 링크와 원격 복제본을 유지하기 위한 계약이다.

모델은 이미 잡 예약과 Fedipub 콜백을 포함한다. 목표 계층을 근거로 현 구현의 이러한 협력을 없다고 간주하거나, 모든 모델 부작용이 정적 검사로 격리되었다고 주장하지 않는다.
