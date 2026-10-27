---
id: ruby-news-clients
type: module-design
status: active
title: 외부 데이터 클라이언트
parent: ruby-news-architecture
---

# 외부 데이터 클라이언트

코드 및 `ruby-news-layers`를 바탕으로 작성했으며 사용자 검토와 승인을 거쳤다. 외부 API·SDK의 요청, 응답 해석, 통신 실패를 호출자가 사용할 값으로 바꾸는 infrastructure 경계다.

client는 받은 값으로 외부 통신을 수행하며 도메인 모델이나 상위 application/presentation 상수에 의존하지 않는다. 레코드 생성, 계정 매칭, HTTP 세션과 렌더링은 소유하지 않는다. GithubEmails가 GitHub 이메일 조회의 헤더·타임아웃·JSON 해석을 담당하는 것이 대표 사례다.

이 디렉터리의 경계가 모든 외부 I/O가 여기만 존재함을 뜻하지 않는다. AI·Fedipub·소셜 서비스 등의 별도 협력은 `ruby-news-architecture`에서 구분한다. 통신 실패 시 반환값과 예외는 client별 계약을 확인하고 하나의 공통 재시도 정책이 있다고 가정하지 않는다.
