# 테스트 데이터베이스 격리

Minitest와 RSpec은 각각 실행 안에서는 트랜잭션을 사용하지만, 별도의 테스트 프로세스가 같은 PostgreSQL DB에 접근하면 fixture 재적재와 다른 프로세스의 쓰기가 충돌한다. `parallelize(workers: 1)`도 다른 터미널이나 worktree의 실행까지 제한하지 않는다.

2026-09-26 PostgreSQL 로그에서는 10:08:20 KST의 `posts` INSERT와 fixture DELETE/INSERT, 10:08:53 KST의 `articles.likers_count` UPDATE와 fedipub actor UUID UPDATE 사이에 교착이 기록됐다. 같은 시각 `log/test.log`에는 서로 다른 Rails 테스트 프로세스 세 개(pid 63702, 63804, 64225)의 실행이 남아 있었다. 앱의 단일 트랜잭션 경합으로 해석하기 전에 외부 테스트 러너 사이의 DB 공유를 확인해야 한다.

`test/test_helper.rb`와 `spec/rails_helper.rb`는 Rails 환경을 로딩한 직후, schema 유지보수나 fixture 작업 전에 `TestDatabaseGuard`로 비차단 파일 잠금을 획득한다. 같은 DB를 쓰는 두 번째 프로세스는 기다리지 않고 한국어 안내와 함께 실패한다. 첫 번째 프로세스가 종료되면 OS가 잠금을 자동으로 해제한다. 잠금 파일 자체는 남아도 다음 실행을 막지 않으므로 삭제할 필요가 없다. 실행 중인 잠금 파일을 삭제하면 다른 inode로 잠금이 나뉘어 보호가 깨질 수 있다.

동시에 실행해야 할 때는 실행마다 별도의 PostgreSQL 테스트 DB를 준비하고 `TEST_DATABASE_URL`을 명시한다.

```sh
TEST_DATABASE_URL=postgres://localhost:5432/ra-news_test_worker_a bin/rails test
TEST_DATABASE_URL=postgres://localhost:5432/ra-news_test_worker_b bundle exec rspec
```

가드는 설정된 `TEST_DATABASE_URL`을 바꾸지 않는다. Rails가 해석한 test primary 설정의 host, port, database로 잠금 키를 만들며, username이나 password는 포함하지 않는다. 같은 DB를 다른 사용자로 접근해도 같은 잠금을 사용한다. 생략된 host와 port는 `localhost`, `5432`로 정규화한다. URL, 비밀번호, DB 이름은 오류에 출력하지 않는다.

이미 SimpleCov를 시작한 러너가 잠금 획득을 거절당하면 종료 시 커버리지 기록도 생략한다. 테스트를 시작하지 못한 결과로 기존 `.resultset.json`, `.last_run.json`, `.quality_last_run.json`을 덮지 않으며, 잠금을 획득한 정상 실행의 커버리지는 그대로 기록한다.

잠금 파일은 `Dir.tmpdir` 아래 고정된 `al_news-test-database-locks` 디렉터리의 SHA256 이름으로 저장한다. 같은 OS 사용자와 같은 임시 디렉터리를 사용하는 worktree와 두 테스트 러너가 공유한다. 이 보호는 한 호스트의 협력하는 러너 사이에 적용된다. 호스트 별칭(`localhost`와 `127.0.0.1` 등), 서로 다른 임시 디렉터리, 다른 컴퓨터의 러너, helper를 로딩하지 않는 직접 DB 작업까지 같은 잠금으로 통합하지는 않는다. 병렬 CI에서는 실행별 PostgreSQL DB 격리를 유지한다.

가드 자체의 회귀 테스트는 PostgreSQL 연결 없이 실제 자식 Ruby 프로세스의 파일 잠금으로 검증할 수 있다. Rails 테스트의 DB 검증은 PostgreSQL을 사용한다.

```sh
ruby test/lib/test_database_guard_test.rb
```
