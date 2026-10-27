---
id: ruby-news-oauth
type: module-design
status: active
title: OAuth 계정 매칭과 가입
parent: ruby-news-architecture
depends-on: [ruby-news-domain, ruby-news-clients]
references: [ruby-news-layers]
---

# OAuth 계정 매칭과 가입

코드와 채택된 계층 문서를 바탕으로 작성했으며 사용자 검토와 승인을 거쳤다. 외부 인증 결과를 로컬 로그인 또는 추가 가입 정보로 변환하고, 가입 레코드 생성과 트랜잭션을 소유한다. HTTP 세션·params·cookies·request는 전달받지 않는다.

## 매칭 계약

provider/uid에 연결된 계정을 먼저 사용한다. 이메일 기반 기존 계정 매칭은 검증된 이메일에만 허용하며 Apple relay 이메일과 빈 이메일은 제외한다. 이 조건을 편의상 완화하면 다른 사용자 계정에 연결될 수 있다.

Callbacks는 불변 결과 SignIn 또는 CompleteSignup을 반환한다. 가입 payload의 세션 저장·삭제 및 로그인·리다이렉트는 controller가 담당한다. Registration은 세션이 아니라 signup_payload 값을 받는다.

## 검사 한계

사용자 확인: 계층 검사는 부분 적용이며 요청 객체 전달이나 동적 참조까지 보장하지 않는다. 정확한 패키지 범위와 허용·금지 방향은 `ruby-news-layers` 한 곳에서 소유한다. 그 문서에 남은 후속 과제는 이번 스펙 설정에서 수정하거나 해결된 것으로 간주하지 않는다.
