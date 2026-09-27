# 계층 경계와 Packwerk 검사

Rails MVC 구조는 그대로 두고, 책임이 섞이기 쉬운 곳부터 계층을 선언해 [Packwerk](https://github.com/Shopify/packwerk)와 [packwerk-extensions](https://github.com/rubyatscale/packwerk-extensions)의 Layer Checker로 의존 방향을 검사한다(#1014). 전체 코드베이스를 한 번에 계층화하지 않는다. 한 흐름에 먼저 적용하고 넓혀 간다.

## 계층

`packwerk.yml`의 `layers`는 위에서 아래 순서다. 패키지는 같은 층이나 **아래 층에만** 의존할 수 있다.

| 계층 | 책임 | 목표 배치(현재 검사 범위는 아래 표 참조) |
| --- | --- | --- |
| presentation | HTTP `params`·세션·`current_user`, 리다이렉트, Phlex 렌더링 | `app/controllers`, `app/views`, `app/components` |
| application | 유스케이스 순서, 트랜잭션, 여러 모델의 조합 | `app/functions/*`, `OperationService` 상속 서비스 |
| domain | 공통 불변 조건과 영속성: 검증, 연관, 스코프 | `app/models` |
| infrastructure | 외부 API·SDK 연동 | `app/clients` |

`package.yml`이 없는 코드는 모두 루트 패키지(`package.yml`)에 속한다. 루트 패키지는 `layer`가 없어 계층 검사에서 빠진다. 루트를 참조하든 루트에서 참조받든 위반이 되지 않는다(`Packwerk::Layer::Package#can_depend_on?`). 새 패키지와 루트 코드 사이의 참조는 검사하지 않지만, 이미 계층을 선언한 다른 패키지와의 참조에는 영향을 준다.

`enforce_dependencies`는 모든 패키지에서 끈다. 이 도입에서는 계층 방향만 검사하고, 패키지 사이의 명시적 의존 선언(`dependencies:`)은 쓰지 않는다.

## 적용한 흐름: OAuth 로그인·가입

이 흐름을 고른 이유는 네 계층을 모두 거치기 때문이다. 콜백 컨트롤러, 세션 기반 가입 단계, 매칭·가입 트랜잭션, 모델 두 개(User, OauthAccount)와 GitHub API 호출이 들어 있다. 인증 경로라 잘못 섞였을 때의 비용도 크다.

```
[presentation] Users::OmniauthCallbacksController
                  └──▶ OauthAccounts::Callbacks.handle_callback
               Users::OauthRegistrationsController
                  ├──▶ OauthAccounts::Callbacks.suggest_username
                  ├──▶ OauthAccounts::Registration.register_user
                  └──▶ Views::Users::OauthSignup (렌더링)

[application]  OauthAccounts::Callbacks ───▶ User, OauthAccount [domain]
                  └──▶ GithubEmails [infrastructure]
               OauthAccounts::Registration ───▶ User, OauthAccount [domain]
```

| 패키지 | 계층 | 구성 |
| --- | --- | --- |
| `app/controllers/users` | presentation | `Users::OmniauthCallbacksController`, `Users::OauthRegistrationsController`, 그 밖의 Devise 컨트롤러 |
| `app/views/users` | presentation | `Views::Users::OauthSignup`, 인증·프로필 편집 화면, jbuilder |
| `app/functions/oauth_accounts` | application | `OauthAccounts::Callbacks`, `OauthAccounts::Registration` |
| `app/models` | domain | `User`, `OauthAccount`, `Configs::*Oauth` 등 모든 모델 |
| `app/clients` | infrastructure | `GithubEmails` 등 모든 외부 API client |

Packwerk 패키지는 디렉터리 단위라서 domain과 infrastructure는 흐름의 파일만 떼어 낼 수 없다. `app/models`와 `app/clients`를 통째로 패키지로 만들었다. 두 디렉터리는 원래 그 계층의 책임만 갖기 때문이다. 흐름 쪽 세 패키지는 `app/controllers/users`, `app/views/users`, `app/functions/oauth_accounts`다. application 디렉터리는 OAuth 흐름 전용이지만, 두 presentation 디렉터리는 다른 Devise 컨트롤러와 프로필 편집 화면도 포함한다. `app/components`와 `app/services`는 목표 계층 배치만 정했으며 현재는 루트 패키지라 검사하지 않는다.

### 허용 방향과 금지 방향

- presentation → application → domain → infrastructure 방향만 허용한다.
- application이 presentation을 참조하면 안 된다. 예를 들어 `OauthAccounts::*`가 `Users::*` 컨트롤러 상수나 `Views::Users::*`를 참조하는 경우다. 다른 컨트롤러와 `Views::*`는 루트 패키지이므로 현재 검사에서 빠진다.
- domain이 흐름의 application·presentation을 참조하면 안 된다. 예를 들어 모델이 `OauthAccounts::Callbacks`를 부르는 경우다.
- infrastructure는 domain도 참조하면 안 된다. client는 받은 값으로 외부 API만 호출한다.

도입하면서 `OauthAccounts::Callbacks` 안에 있던 GitHub `/user/emails` 호출(Faraday, 헤더, 타임아웃, JSON 파싱)을 `GithubEmails`(`app/clients/github_emails.rb`)로 옮겼다. application이 외부 API의 세부 사항을 직접 다루지 않게 하고, 그 의존이 infrastructure 패키지 참조로 드러나게 하려는 목적이다.

## 기존 위반(기준선)

기존 위반은 `package_todo.yml`에 기준선으로 남긴다. `bin/packwerk check`는 이 목록에 없는 새 위반이 생기면 실패한다. 목록에 있는데 이미 고쳐진 stale 항목이 있어도 실패한다.

| 파일 | 참조 | 원인 | 방침 |
| --- | --- | --- | --- |
| `app/clients/discord_client.rb` | `Configs::Discord` | client가 webhook 설정을 DB에서 직접 읽는다 | 설정을 인자로 받게 한다(#1029) |
| `app/clients/slack_client.rb` | `Configs::Slack` | 위와 같다 | #1029 |
| `app/clients/mastodon_client.rb`, `twitter_client.rb` | `Preference` | OAuth 설정을 `Preference`에서 직접 읽는다 | #1029 |

위반을 고치면 `bin/packwerk update-todo`로 목록을 줄인다. 새 위반을 목록에 추가하는 용도로 `update-todo`를 쓰지 않는다. 새 패키지 도입 시 불가피한 기존 위반을 추가한다면 이 문서의 기준선 표에 원인과 방침을 적고 PR 설명에 이유를 남긴 뒤 갱신한다.

## 검사로 보장할 수 없는 경계

Packwerk는 **앱 안의 패키지에 정의된 상수 참조**만 본다. 다음은 검사 밖이므로 리뷰와 테스트로 지킨다.

- **덕 타이핑된 요청 객체.** `session`, `params`, `request`, `cookies`를 인자로 넘기면 상수 참조가 아니라서 잡히지 않는다. 현재 `OauthAccounts::Callbacks.handle_callback(auth:, session:)`이 세션에 직접 쓴다. 검사에 드러나지 않는 설계상 위반이며 #1028에서 걷어낸다.
- **젬 상수.** `ActionDispatch::Request`, `Faraday` 같은 젬 상수는 어느 패키지에도 속하지 않는다. application이 `Faraday`를 직접 불러도 검사는 통과한다.
- **런타임 호출.** 문자열로 대상을 정하는 `constantize`, 동적으로 메서드를 선택하는 `send`, `public_send` 등의 의존은 보이지 않는다. 모델 콜백의 `IndexNowJob.set(...).perform_later` 같은 잡 상수 참조는 정적 검사 대상이지만, 현재 `app/jobs`가 루트 패키지여서 계층 위반이 되지 않는다.
- **루트 패키지.** 계층이 없는 코드(`app/services`, `app/jobs`, 흐름 밖 컨트롤러 등)와 주고받는 참조는 검사하지 않는다.
- **Ruby 파일만 검사한다.** `packwerk.yml`의 `include`가 `{app,lib}/**/*.{rb,rake}`라서 `app/views/users/*.json.jbuilder`는 검사하지 않는다.
- **같은 패키지 안.** `app/models`처럼 넓은 패키지 안의 의존(모델끼리)은 검사 대상이 아니다.

## 운영

```sh
bin/packwerk validate        # package.yml·packwerk.yml 설정 검증
bin/packwerk check           # 계층 위반 검사(새 위반·stale 항목에서 실패)
bin/packwerk-layer-probe     # 상위 계층을 참조하는 임시 파일을 넣어 검사가 실제로 실패하는지 확인
bin/packwerk update-todo     # 위반을 고친 뒤 package_todo.yml 갱신
```

CI의 `boundaries` 잡과 `bin/ci`가 앞의 세 명령을 실행한다. `boundaries`는 앱 부팅에 필요한 libvips와 확장 구성이 포함된 PostgreSQL 18(`ra-pg`) 서비스를 준비한다. `RAILS_ENV=test`와 `TEST_DATABASE_URL`을 잡 전체에 적용하고, 전용 DB의 primary 스키마를 로드한 뒤 검사한다. `bin/packwerk-layer-probe`는 음성 테스트다. 설정 오타 등으로 `enforce_layers`가 꺼지면 `check`는 조용히 초록으로 남는데, 이 스크립트가 그런 경우를 잡는다. 동일한 임시 파일을 쓰므로 probe를 동시에 여러 번 실행하지 않는다(기존 파일이 있으면 abort한다). `check`가 성공 코드로 종료되면 위반 메시지 유무와 관계없이 실패 사유를 출력한다. 스크립트는 application·domain·infrastructure 패키지에 각각 상위 계층을 참조하는 파일을 임시로 만들고, `packwerk check`가 세 건 모두를 위반으로 보고하는지 확인한 뒤 파일을 지운다.

### 흐름을 넓힐 때

1. 흐름 전용 디렉터리(`app/functions/<도메인>` 등)에 `package.yml`을 둔다. `enforce_layers: true`로 켜고 `layer`를 지정한다.
2. `bin/packwerk check`로 드러난 위반을 확인한다. 고칠 수 있는 것은 고치고, 불가피하게 남기는 기존 위반은 이 문서의 기준선 표에 원인과 방침을 적고 PR 설명에 이유를 남긴 뒤 `update-todo`한다.
3. 새 패키지에 대한 음성 케이스가 필요하면 `bin/packwerk-layer-probe`의 `PROBES`에 추가한다.

## 후속 과제: GitHub 이메일 조회 실패 안내

GitHub에서 검증된 이메일을 얻지 못하면 기존 이메일 계정 매칭을 건너뛰고 가입 화면으로 간다. 현재 화면은 빈 이메일을 readonly로 표시하므로 제출해도 가입할 수 없다. 계층 경계 도입과 별도로, 이 경우 가입 화면 대신 `user:email` 권한과 재인증을 안내하도록 콜백·화면 흐름을 개선해야 한다. 이번 변경의 HTTP 상태·예외 유형 경고 로그는 운영 진단을 위한 것이며 이 가입 흐름을 해결하지 않는다.
