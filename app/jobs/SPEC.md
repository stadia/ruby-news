---
id: ruby-news-jobs
type: module-design
status: active
title: 수집 및 비동기 작업
parent: ruby-news-architecture
depends-on: [ruby-news-domain, ruby-news-processing, ruby-news-clients]
---

# 수집 및 비동기 작업

코드 분석으로 도출한 경계이며 사용자 검토와 승인을 거쳤다. HTTP 요청 밖에서 수집·기사 처리·재처리·외부 배포·답글 알림을 실행한다. 작업 인자는 저장된 레코드 식별자나 수집원 목록이며 실행 시 최신 상태를 다시 확인한다. 서비스의 처리 순서와 모델의 데이터 계약을 중복 소유하지 않는다.

## 수집

Site별 잡이 RSS·페이지·Gmail·YouTube·Hacker News·Reddit 유입을 처리한다. RSS는 마지막 확인 시점과 기존 origin_url로 신규 후보를 좁힌다. RSS의 인증 거부는 Site 폐기로, 속도 제한은 건너뜀으로 처리한다. 이 정책을 모든 수집원에 공통 적용된 것으로 일반화하지 않는다.

## 재실행과 부작용

ArticleJob은 kept 기사만 처리 서비스로 넘긴다. 일시 실패 기사 재처리는 ArticleBatchJob의 제한된 조회 기간을 따른다. 큐의 재시도만으로 모든 외부 부작용이 정확히 한 번 실행된다고 보장하지 않는다. 각 전달 작업의 중복 방지·전송 기록과 삭제 상태를 유지해야 한다.

연합·소셜 삭제와 답글 알림은 공개 데이터의 생명주기와 결합되어 있다. 관련 작업을 단순 비동기 최적화로 취급해 콜백 없이 생략하지 않는다. 모듈 사이 호출 방향은 `ruby-news-architecture`에 기록한다.
