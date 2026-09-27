# 디자인 시스템 리뷰 — 시맨틱 토큰과 가시성

- 일자: 2026-09-22
- 범위: `app/assets/tailwind/{tokens,application,site}.css`, RubyUI 컴포넌트(`app/components/ruby_ui/`), `DESIGN.md`
- 방법: OKLCH 값을 sRGB로 변환해 WCAG 2.x 대비비와 APCA Lc를 계산. 사용처는 `app/` 전체의 유틸리티 클래스를 집계.

## 총평

앱 전용 토큰 레이어(`bg-app`, `text-content-*`, `bg-brand-solid` 등)는 잘 설계되어 있고 적용률도 높다. 문제는 그 아래 RubyUI/shadcn 토큰 레이어(`--primary`, `--background`, `--accent` …)가 앱 토큰과 연결되지 않은 채 독립된 값을 갖는다는 점이며, 대비 실패 대부분이 여기서 나온다.

## 잘 된 점

- 하드코딩 팔레트 83건이 5개 파일에만 남아 있다(madmin 관리자 화면, OAuth 브랜드 버튼). 반면 `text-content` 124, `text-content-secondary` 101, `text-content-muted` 94건 등 시맨틱 토큰이 표준으로 정착했다.
- OKLCH primitive → semantic → utility 3단 구조, `prefers-reduced-motion` 처리, 인라인 스크립트로 테마 깜빡임 방지.
- `bg-brand-solid`(5.02:1), `bg-danger-solid`(4.83), `bg-info-solid`(5.17) 통과. 라이트 `info-text`는 이미 대비 보정됨(`tokens.css`).

## 발견 사항

상태: **해결** = 이번 커밋에서 수정, **미해결** = 후속 작업.

### P0 — 화면에서 실패

| # | 문제 | 수정 전 | 수정 후 | 상태 |
|---|---|---|---|---|
| 1 | RubyUI Button 기본값(primary): 흰 글자 on `--primary`(green-500). 로그인, 비밀번호, 댓글/포스트 제출, 블로그 에디터, 회원정보 폼, NavBar CTA 등 약 15곳 | 2.20:1 | 5.02:1 | 해결 |
| 2 | 라이트 hover/secondary: `--secondary-foreground: var(--primary)`로 연회색 위 초록 글자. Dropdown/Select 항목, ghost/outline hover, secondary 버튼 | 2.11:1 | foreground 사용 | 해결 |
| 3 | Link 기본 variant와 InlineLink: `text-primary`(green-500) on white | 2.30:1 (라이트) | 5.02 / 10.23 | 해결 |
| 4 | 라이트 포커스 링: `ring-brand`(31곳)가 `--brand-primary`(green-500)로 고정 | 2.19:1 | 4.80:1 | 해결 |

### P1 — 구조 문제

5. **토큰 레이어 불일치 (해결)**: `body`는 `bg-app`(slate neutral-900, L 0.208)인데 RubyUI Card, Dialog, Dropdown, Popover, Select, Input은 `bg-background`(무채색 0.145)를 써서, 다크 모드에서 팝오버/다이얼로그가 페이지보다 어둡고 색조도 섞였다. → RubyUI 표면/글자/테두리 토큰을 모두 앱 토큰 alias로 연결했다(`application.css` 공통 블록).

   | RubyUI | 앱 토큰 | 다크 / 라이트 |
   |---|---|---|
   | `--background` | `--color-bg-primary` (`bg-app`) | n900 / n50 |
   | `--card`, `--popover` | `--color-bg-elevated` (`bg-surface-elevated`) | n800 / white |
   | `--secondary`, `--muted` | `--color-bg-tertiary` (`bg-surface-muted`) | n700 / n200 |
   | `--accent` | `--color-bg-hover` (`bg-surface-hover`) | n600 / n300 |
   | `--foreground` 계열 | `--color-text-primary` | |
   | `--muted-foreground` | `--color-text-muted` | |
   | `--border` | `--semantic-border` (신규) | n700 / n300 |
   | `--input` | `--color-border-light` | n600 / n400 |

   - 떠 있는 표면(Dropdown, Popover, Select, Dialog, AlertDialog)은 `bg-popover`, Card는 `bg-card`로 바꿔 페이지보다 한 단계 위에 오게 했다. Input/Textarea는 `bg-background`(페이지 색)를 유지해 카드 안에서 안쪽으로 들어간 느낌을 준다.
   - `--color-border`는 Tailwind 테마 변수와 이름이 겹쳐(레이어 순서에 따라 `var(--border)`와 순환 참조 위험) 새 `--semantic-border`를 두고 이를 참조한다.
   - TabsList 글자는 `muted` 위에서 4.04:1이라 `text-content-secondary`(8.39:1)로 바꿨다.
   - 기본 테두리(`* { border-color: var(--border) }`)가 다크 white/10%에서 neutral-700, 라이트 0.922에서 neutral-300으로 조금 진해졌다. 색을 지정하지 않은 `border`가 모두 영향을 받는다.
   - 브라우저 확인: 홈(카드, 사이드바, 사용자 드롭다운), 프로필 활동 탭을 두 테마에서 확인.
6. **`text-content-disabled`를 정보 텍스트에 사용 (미해결)**: 1.9–2.5:1. 빈 상태 메시지 4곳(`views/profiles/{activity,boost,follow,like}_list.rb`, `views/blog_posts/index.rb`), `components/users/user.rb:52`의 10px 대문자 라벨. 원인은 `DESIGN.md` 마이그레이션 표의 `text-gray-500 → text-content-disabled`. → `text-content-muted`로 교체하고 표 수정.
7. **상태 색을 글자색으로 사용 (미해결)**: danger/info에는 `-text` 토큰이 있으나 success/warning에는 없다. 라이트에서 warning 배지 1.90, success 배지 2.68, Boost 활성(`text-success`) 2.95. 다크 success 배지 4.12. → `--semantic-success-text`, `--semantic-warning-text` 추가.
8. **Destructive 변형 (해결)**: 글자색과 배경색이 거의 같았음(다크 1.32, 라이트 1.00). 호출부는 없었으나 잠재 결함. → `--destructive`를 danger-solid로, 글자는 흰색으로(4.83:1).
9. **비텍스트 대비 3:1 미달 (미해결)**: 입력 테두리 — RubyUI 1.25–1.26, `border-border-muted` on `surface-muted` 다크 1.37 / 라이트 2.08. 모바일 메뉴 포커스 outline(`site.css`) 2.91.
10. **경계선 조합 (미해결)**: 다크 `text-content-muted` on `bg-surface-muted` 4.04, 라이트 `text-accent-text` on `bg-surface-muted` 4.08.

### P2 — 문서와 정합성 (미해결)

- `DESIGN.md`와 실제 값 불일치: `bg-app = oklch(0.145 0 0)`로 적혀 있으나 실제 neutral-900(라이트 neutral-50), Card 라운드 12px로 적혀 있으나 실제 `rounded-lg` = 10px(`--radius: 0.625rem`), 문서 기준 "APCA Lc ≥ 60"을 muted 텍스트(Lc 48–51)가 충족하지 못함.
- 네임스페이스 충돌: `tokens.css`가 Tailwind의 `--color-border`, `--color-info`, `--text-*`, `--radius-*`, `--shadow-*`를 `@layer base`에서 재정의. `var(--color-border)`는 neutral-700인데 `border-border` 유틸리티는 white/10%. `--radius-lg: 0.75rem`은 적용되지 않는 값.
- `color-scheme` 미선언: 다크 테마에서도 네이티브 스크롤바, 폼 컨트롤, 자동완성 배경이 밝게 남는다.
- PWA `theme_color: #7F1D1D`(짙은 빨강)가 초록 브랜드와 불일치, 테마별 `<meta name="theme-color">` 없음.

## 이번 수정 내역 (P0 1–4, P1-8)

- `application.css`: 다크/라이트 `--primary` → `var(--semantic-brand-solid)`, `--destructive` → `var(--semantic-danger-solid)`, `--destructive-foreground` → 흰색, 라이트 `--secondary-foreground` → `var(--foreground)`, 라이트 `--ring` → `var(--semantic-brand-solid)`, `--color-brand` → `var(--semantic-brand)`.
- `tokens.css`: `--semantic-brand` 추가(다크 green-500, 라이트 green-700).
- `--primary`/`--destructive`는 이제 "흰 글자를 얹는 solid 배경" 전용이다. 그대로 글자색으로 쓰면 다크에서 3.55:1(링크), 3.69:1(에러)로 미달하므로, 글자 용도를 앱 토큰으로 옮겼다.
  - Button/Link의 link variant, InlineLink: `text-primary` → `text-link hover:text-link-hover`
  - FormFieldError, Alert(destructive), `views/oauth/result.rb`: `text-destructive` → `text-danger-text`

- 흰 글자를 얹지 않는 비텍스트 지시자는 `brand` 토큰으로 옮겼다. green-700을 그대로 쓰면 다크 `bg-surface` 대비 2.91:1이 되기 때문이다(guard 검증 중 발견).
  - Radio 테두리, Checkbox/Radio checked 테두리: `border-primary` → `border-brand` (다크 6.36 / 라이트 5.02)
  - Switch 트랙: `bg-primary` → `bg-brand` (다크 6.36 / 라이트 5.02)
  - Progress: `bg-primary` → `bg-brand` (인디케이터 vs 트랙 다크 4.42 / 라이트 3.67)

**규칙**
- `bg-primary`, `bg-destructive`는 흰 글자를 얹는 solid 배경에만 쓴다.
- 글자색: 링크는 `text-link`, 에러 문구는 `text-danger-text`. `text-primary`, `text-destructive`는 쓰지 않는다.
- 비텍스트 지시자(테두리, 트랙, 링, 진행 막대): `brand` 토큰(`border-brand`, `bg-brand`, `ring-brand`)을 쓴다.

- 브라우저 확인 중 발견: `views/sessions/new.rb`의 "비밀번호를 잊으셨나요?", "인증 메일 재전송" 링크가 `variant: :primary`에 글자색만 덮어써서 초록 배경 위 회색 글자로 렌더링되고 있었다(수정 전부터 있던 문제로, 이번 변경으로 배경이 더 어두워져 악화됨). 테두리 버튼(`variant: :outline` + `border-border-muted bg-transparent text-content-secondary hover:bg-surface-hover`)으로 바꿔 로그인(주) > 회원 가입(채움) > 비밀번호 찾기(테두리) 계층을 유지.

검증: `bin/rails tailwindcss:build` 성공, `bin/rails test` 1066 runs 0 failures, Chrome에서 로그인 페이지 라이트/다크 테마와 포커스 링, hover 상태 확인.

### 잔여 영향과 기존 미달 (후속 작업)
- 라이트 테마에서 `bg-brand/N` 배지 틴트와 NavBar 상단 `border-t-brand`가 한 톤 어두워진다(의도된 변화).
- 다크 에러 입력 테두리 `border-destructive/50`이 1.84에서 1.28:1로 조금 더 낮아졌다. 원래도 3:1에 미달했으며 P1-9(입력 테두리)와 함께 처리한다. 대상: `components/users/pwd_form.rb:99`, `input_styling.rb:11`, `views/confirmations/new.rb:55`.
- 이전부터 있던 미달:
  - 라이트 primary 버튼 hover(`hover:bg-primary/90`)의 흰 글자: 4.22:1
  - 라이트 `text-danger-text` on `bg-destructive/10`: 3.96:1 (`views/oauth/result.rb:49`)
  - fedipub 레이아웃 skip link `focus:bg-brand` 흰 글자 (다크): 2.28:1. `bg-brand-solid`로 바꾸면 해결된다.

### 브라우저 확인에서 추가로 발견 (이번 변경 이전부터 존재)
- **(해결) 다크 테마 미체크 체크박스/라디오가 흰색으로 채워졌다.** `@tailwindcss/forms`의 기본 흰 배경 때문. → `bg-transparent` 지정, 체크박스 테두리는 `border-content-muted`(다크 6.97 / 라이트 7.22:1).
- **(해결) 라이트 테마 미체크 체크박스 테두리가 거의 안 보였다.** `border-input` 1.26:1 → 위 수정으로 함께 해결.
- **(해결) 푸터 테마 전환 버튼 2개에 접근 가능한 이름이 없었다.** `aria-label`(`layout.theme_light`/`layout.theme_dark`, ko/en/ja) 추가, 아이콘 SVG는 `aria-hidden`.
- **(해결) 다크 테마 드롭다운이 페이지보다 어두웠다.** P1-5 통합으로 해결(n800 on n900).
- **(해결) 라이트 테마 경고 배너 글자가 4.28:1로 AA에 조금 못 미쳤다.** RubyUI Alert(destructive)의 `text-danger-text`(red-600) on `bg-destructive/5`. 라이트 `info-text`처럼 텍스트 전용 토큰만 red-700(`--semantic-danger-solid-hover`)으로 낮췄다. 배너 5.74, OAuth 오류 문구 5.55(기존 3.96), 댓글 폼 오류 4.70:1. 다크는 변경 없음(6.31:1). (참고) "이미 로그인되어 있습니다."처럼 단순 안내도 Devise `flash[:alert]`라 빨간 경고 스타일로 표시된다.
- **(참고) 로케일 파일이 i18n-tasks 정규화 순서가 아니다.** `i18n-tasks check-normalized`가 ko/en/ja 모두 실패한다(이번 변경 전부터). 정규화하면 약 190줄이 재배치되므로 별도 커밋으로 처리 권장.
- 다크 테마 스위치의 thumb이 `bg-background`(거의 검정)라 켜진 상태에서 초록 트랙 위 검은 원으로 보인다. 대비는 8.62:1로 충분하나 일반적인 흰 thumb 관례와 다르다.

## 후속 권장 순서

1. ~~`--background`/`--card`/`--popover`/`--border`/`--input`을 앱 토큰 alias로 통합 (P1-5)~~ 완료
2. success/warning `-text` 토큰 추가 (P1-7)
3. 빈 상태 메시지 `text-content-muted`로 교체, `DESIGN.md` 마이그레이션 표 수정 (P1-6)
4. `.theme-dark { color-scheme: dark }` / `.theme-light { color-scheme: light }` (P2)
5. 입력 테두리 대비 보강 (P1-9)
6. `DESIGN.md` 값 동기화, `tokens.css`의 Tailwind 네임스페이스 재정의 정리 (P2)

## 후속 처리 (2026-09-27, #994 종료)

위 "미해결"과 "후속 권장 순서" 항목을 모두 처리했다. 대비 값은 OKLCH → sRGB 변환 후 WCAG 2.x 대비비다.

| 항목 | 변경 | 수정 후 |
|---|---|---|
| P1-7 success/warning 글자 | `--semantic-success-text`(다크 lime-400 / 라이트 lime-800), `--semantic-warning-text`(amber-400 / amber-800) 추가. Badge, Alert, Boost 활성, OAuth 성공 아이콘, 글자 수 경고를 `text-*-text`로 교체 | Badge 10% 틴트 기준: 라이트 bg-app 위 success 6.11 / warning 6.33, 다크 bg-surface 위 8.29 / 7.18 |
| P1-6 `text-content-disabled` 정보 텍스트 | 빈 상태 메시지 5곳과 `users/user.rb` 라벨을 `text-content-muted`로. DESIGN.md 마이그레이션 표 수정 | 다크 6.97 / 라이트 7.22 |
| P1-9 입력 테두리 | `--input` → `--semantic-input-border`(neutral-500). RubyUI Input/Textarea는 `border-input`. 로그인·비밀번호·인증 메일·기사 URL·헤더 검색·원격 계정 조회·블로그 편집은 `bg-app border-input`. Post 답글은 `bg-surface`, 회원 폼은 `bg-surface/50` 배경을 유지하며 테두리만 `border-input`으로 교체. 에러는 `border-danger-text` | 다크 bg-app 3.74, bg-surface 3.06 / 라이트 4.55. 에러 다크 6.46 / 라이트 6.19 |
| P1-9 모바일 메뉴 포커스 outline | `--semantic-brand-solid` → `--semantic-brand` | 다크 7.84 / 라이트 4.80 |
| P1-10 경계선 조합 | 입력 placeholder는 배경을 `bg-app`으로 바꿔 해소(다크 4.04 → 6.97). 작은 아바타 폴백은 `bg-surface text-accent-text` | 라이트 4.08 → 4.58 |
| 라이트 primary hover | RubyUI Button/Link `hover:bg-primary/90` → `hover:bg-brand-solid-hover`, destructive 링크도 `[a&]:hover:bg-danger-solid-hover`(일반 button에는 hover 없음) | 4.22 → 7.13 |
| fedipub skip link | `focus:bg-brand` → `focus:bg-brand-solid` | 다크 2.28 → 5.02 |
| `color-scheme` | `.theme-dark { color-scheme: dark }`, `.theme-light { color-scheme: light }` (`tokens.css`) | 스크롤바·폼 컨트롤이 테마를 따름 |
| DESIGN.md 동기화 | 표면·글자·테두리 값을 실제 토큰으로, radius 표(`--radius: 0.625rem` 기준), APCA는 참고 지표로 낮추고 WCAG 2.x AA를 기준으로 명시 | |
| `tokens.css` 네임스페이스 | `--color-{success,warning,error,info}`, `--text-*`, `--radius-*`, `--shadow-*`, `--font-*`, `--leading-*`, `--ease-*` 재정의 제거. 기본값과 다른 `--radius-2xl`은 `application.css`의 `@theme inline`으로 옮겨 24px를 유지한다. info는 `--status-info` | `rounded-2xl` 24px 복구, 나머지 제거 항목은 기본값과 같거나 적용되지 않던 값 |
| PWA 색 | manifest `theme_color`/`background_color` `#7F1D1D` → `#0f172a`(다크 bg-app). head에 테마별 `<meta name="theme-color">`, theme-color 메타를 init 스크립트 앞에 두고 pre-paint 스크립트와 theme-toggle이 저장된 테마에 맞게 media를 바꾼다. 쓰이지 않고 JSON도 깨져 있던 `manifest.js.erb` 삭제 | |
| 하드코딩 팔레트 | madmin 레이아웃은 앱 Tailwind(`app.css`)를 불러오지 않아 팔레트 클래스가 원래 적용되지 않았다. 토큰으로 옮기지 않고 madmin CSS 구조(`header`, `table`, `btn btn-*`)로 정리. `btn-success`/`btn-warning`은 madmin에 없어 `btn-secondary` | OAuth 브랜드 버튼만 예외로 남음 |
| 푸터 테마 전환 버튼 이름(브라우저 확인 중 발견) | 0af675bd에서 붙인 `aria-label`이 반대였다. 다크 모드에서 보이는 버튼은 라이트로 바꾸는데 "다크 모드로 전환"으로 읽혔다. 누르면 바뀔 테마로 교체 | |
| 로케일 정규화 | `i18n-tasks normalize` (별도 커밋) | |
| 검토: Devise 안내 flash | 유지. Flash 톤은 메시지가 아니라 키로 정해지고, Devise는 거부된 동작(이미 로그인됨 등)에 `:alert`를 쓴다 | |
| 검토: 스위치 thumb | `bg-background` → `bg-brand-foreground`(흰색). 켜짐/꺼짐 모두 일반적인 흰 thumb 관례를 따른다 | |

검증: `bin/rails tailwindcss:build`, `bin/rails test`(1289 runs 0 failures), `bundle exec rspec`(70 examples 0 failures), Chrome에서 로그인·홈·프로필 빈 상태·계정 설정·비밀번호 변경(에러 상태) 화면을 라이트/다크 두 테마로 확인하고, 계산 대비값을 페이지 안에서 다시 측정(에러 테두리 다크 6.48 / 라이트 6.19, 입력 테두리 다크 3.76, 빈 상태 7.24 / 6.96, 성공 알림 6.41).
