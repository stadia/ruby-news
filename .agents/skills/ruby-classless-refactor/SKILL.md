---
name: ruby-classless-refactor
description: Ruby 클래스를 모듈/함수/Struct/Data로 리팩터링하는 결정 트리와 변환 레시피. "이 클래스 정말 필요한가?", "함수로 바꿔달라", "Struct로 바꿀 수 있나?", "PORO 정리", "app/functions로 옮겨줘" 같은 요청에 사용한다. 새 클래스를 만들기 전에 검증할 때도 사용한다.
---

# Ruby Classless Refactor

> "Ruby는 객체 지향이지 클래스 지향이 아니다. 클래스는 객체 팩토리일 때만 가치가 있다." — Dave Thomas

**기반 강연**: Dave Thomas, "Eliminating the `class` Keyword from Ruby" — <https://www.youtube.com/watch?v=sjuCiIdMe_4>

**적용 범위**: `app/services/`, `app/functions/`, `app/jobs/`, PORO.
**적용 예외**: ActiveRecord/ActionController/ActiveJob/Draper::Decorator 등 Rails 프레임워크 클래스. 클래스 자체는 손대지 않되, 그 안의 도메인 로직이 두꺼우면 본체만 함수로 분리한다(레시피 D).

### 강연 규칙 → 스킬 매핑

| 강연 규칙 | 위치 |
|---|---|
| 객체 팩토리가 아니라면 클래스 금지 | 메인 질문 + 레시피 A/B |
| 디자인 패턴명을 따르면 클래스 금지 | 안티패턴 신호 #1 |
| Abstract Base Class는 Ruby에 불필요 | 아래 "ABC 관점" + 시나리오 2 |
| 상태가 없으면 클래스 금지 | 결정 트리 D + 레시피 D |
| 생성 직후 추가 호출이 필요하면 클래스 금지 | 안티패턴 신호 #2 |
| 데이터 버킷이면 `Struct`/`Data` 사용 | 안티패턴 신호 #3 + 결정 트리 C + 레시피 C |

### ABC 관점 — 강연의 핵심 주장

`class Person < ApplicationRecord`는 `ActiveRecord::Base`를 통해 약 780개의 메서드를 주입받는다. 이는 C++/Java의 추상 기반 클래스 관행이 Ruby로 이식된 것이며, Ruby는 강타입 언어가 아니므로 타입 안전 보장이 필요 없고 Mixin(`include`/`extend`)이 메서드 주입을 대체한다. `ActionController` 역시 HTTP가 무상태이므로 함수에 더 가깝다.

현실에서는 프레임워크 계약상 상속을 유지하되(시나리오 2), "이상적으로는 클래스가 아니어야 하지만 프레임워크가 강제한다"는 인식 아래 본체만 함수로 분리해 클래스 표면적을 최소화한다.

### 실천적 조언 (강연 결론부)

- **구조보다 인라인이 먼저** — 신규 기능은 인라인 코드나 함수로 시작한 뒤, 객체 팩토리가 진짜로 필요해질 때만 클래스로 승격한다.
- **네임스페이스 중첩은 두세 단계까지** — `Foo::Bar::Baz::Qux::...`는 과도하다.
- **데이터 그루핑은 Hash → Struct → Data 순으로 진화** — 클래스로 직행하지 않는다.
- **변환 후 메서드 수/줄 수가 늘었다면 잘못된 분해** — 90%의 경우 클래스 없이 쓰면 결합도와 복잡도가 줄어들어야 한다.

## 컨벤션 — 메인 질문

새 코드를 만들 때 가장 먼저 답할 한 가지:

> **이건 객체 팩토리인가?** — 인스턴스를 여러 개 만들고 각자 식별 가능한 상태(`@ivar`)를 가지는가? (예: `User`, `Cart`, `ChargingSession`)

- **Yes** → 클래스로 작성. 단 아래 "안티패턴 신호"가 있으면 설계 재고.
- **No**  → 결정 트리로 어떤 도구인지 결정.

### 객체 팩토리여도 의심해야 할 신호

하나라도 해당되면 설계를 다시 본다.

1. **디자인 패턴 이름이 클래스명에 박혀 있다** — `XxxFactory`, `XxxBuilder`, `XxxDecorator`(Draper 외). Ruby는 대부분 언어 차원에서 해결한다.
2. **`new` 직후 setter를 추가로 호출해야 유효해진다** — 생성자에서 모든 필수 값을 받아 invalid 상태가 없게 만든다.
3. **필드명을 `attr_reader` + `initialize` + `==`에서 3회 이상 반복하는 PORO** — 데이터 버킷이지 객체가 아니다. `Struct`/`Data.define`로.

## 결정 트리

### 시나리오 1 — 객체 팩토리가 아니라고 판정된 일반 코드

위에서 아래로 첫 "Yes"에서 멈춘다.

```
B. step :validate/persist 같은 모나드 파이프라인(여러 실패 분기 + 트랜잭션)이 필요한가?
   → Yes: OperationService 상속 클래스로.
   → No: 계속.

C. 동작 거의 없이 필드만 담는 데이터 버킷인가?
   → Yes:
     - 불변이면          → Data.define(:a, :b)         (레시피 C)
     - 가변이면          → Struct.new(:a, :b, keyword_init: true)
     - 메서드 1~2개 더   → Data.define(...) do ... end
   → No: 계속.

D. 생성자에서 받은 인자를 단일 메서드 호출에만 쓰는가?
   (Foo.new(x, y).call 패턴, 외부 상태 없음)
   → Yes: app/functions/ + class << self 순수 함수 → 레시피 A.
   → No: 계속.

E. 여러 private 단계로 쪼개져 있지만 진입점은 하나뿐인가?
   (@lines 같은 누적 변수가 메서드들 사이에서만 공유)
   → Yes: app/functions/ + 인자 명시 전달 → 레시피 B.
   → No: 메인 질문으로 돌아가 "정말 객체 팩토리가 아닌가" 재검토.
        팩토리가 맞다면 클래스 유지 — 변환하지 않는다.
```

### 시나리오 2 — Rails 프레임워크 클래스 안에 도메인 로직이 두껍다

`ApplicationJob`/`ApplicationController`/`ApplicationRecord` 등 상속 클래스 자체는 손대지 않는다. `perform`/액션/콜백 본체가 도메인 로직으로 두꺼우면 본체를 `app/functions/`로 분리해 프레임워크 컨텍스트 없이 단위 테스트 가능하게 만든다. → **레시피 D**.

## 변환 레시피

### A. `Foo.new(x).call` → `app/functions/` 모듈 함수

**언제**: 외부 상태/의존성이 없는 순수 변환. 단일 진입점.

Before:
```ruby
# app/services/price_calculator.rb
class PriceCalculator
  def initialize(pick, plan)
    @pick = pick
    @plan = plan
  end

  def call
    base = @pick.kwh * @plan.unit_price
    base + surcharge
  end

  private

  def surcharge
    @pick.peak_hour? ? @pick.kwh * 50 : 0
  end
end

# 호출부
PriceCalculator.new(pick, plan).call
```

After:
```ruby
# app/functions/price_calculator.rb
module PriceCalculator
  extend Loggable  # 프로젝트가 제공하는 로거 mixin이 있다면 사용

  class << self
    def compute(pick:, plan:)
      base = pick.kwh * plan.unit_price
      base + surcharge(pick)
    end

    private

    def surcharge(pick)
      pick.peak_hour? ? pick.kwh * 50 : 0
    end
  end
end

# 호출부
PriceCalculator.compute(pick: pick, plan: plan)
```

체크:
- 메서드명은 `call` 금지 — `build`/`compute`/`resolve` 같은 도메인 동사
- `private`는 `class << self` 안에서 사용
- 키워드 인자 권장 (호출부 가독성)
- **로깅**: 프로젝트에 로거 mixin 컨벤션이 있는지 먼저 확인. 있으면 `extend`해서 `logger.warn` 형태로 호출. 다른 모듈과 호출 패턴을 일치시킨다.
- **헬퍼가 `protected` 인스턴스 메서드 모듈이면** `extend`로는 못 부른다. `class << self` 블록 안에 `include RssHelper` 형태로 들여와 singleton class의 인스턴스 메서드로 만든다.
- **`class << self` vs `extend self` vs `module_function`**: 강연은 `extend self`를 선호하지만, **이 프로젝트의 컨벤션은 `class << self`로 통일**한다(`extend self`·`module_function`은 쓰지 않는다). 함수 모듈은 `app/functions/`에 두고 `class << self` 블록으로 작성한다. (ref: AGENTS.md "class 대신 module 우선 원칙")

### B. 상태가 있지만 단일 호출만 있는 클래스 → 모듈 함수 + 인자 명시

Before:
```ruby
class ReportBuilder
  def initialize(user, range)
    @user = user
    @range = range
    @lines = []
  end

  def call
    collect_picks
    format_lines
    @lines.join("\n")
  end

  private
  def collect_picks; ... end
  def format_lines; ... end
end
```

After:
```ruby
module ReportBuilder
  class << self
    def build(user:, range:)
      picks = collect_picks(user, range)
      format(picks)
    end

    private

    def collect_picks(user, range) = user.picks.where(created_at: range)
    def format(picks) = picks.map { |p| "..." }.join("\n")
  end
end
```

체크: `@lines` 같은 누적 변수는 메서드 반환값으로 바꾼다. 사이드이펙트는 경계로 밀어낸다.

### C. PORO 데이터 버킷 → `Data.define` 또는 `Struct`

**불변** (선호):
```ruby
# Before
class ChargingResult
  attr_reader :pick_id, :kwh, :cost
  def initialize(pick_id:, kwh:, cost:)
    @pick_id = pick_id; @kwh = kwh; @cost = cost
  end
end

# After
ChargingResult = Data.define(:pick_id, :kwh, :cost)
```

**가변이 필요할 때**:
```ruby
ChargingResult = Struct.new(:pick_id, :kwh, :cost, keyword_init: true)
```

**메서드가 한두 개 필요할 때**:
```ruby
ChargingResult = Data.define(:pick_id, :kwh, :cost) do
  def free? = cost.zero?
end
```

**메서드가 많아지면** 블록을 키우지 말고 동작을 별도 네임스페이스의 독립 함수로 추출한다. 데이터 컨테이너가 비즈니스 로직을 흡수하면 결국 클래스로 회귀한다.

### D. Rails 프레임워크 클래스 안의 두꺼운 도메인 로직 → 함수 위임

Before:
```ruby
class FooJob < ApplicationJob
  def perform(pick_id)
    pick = Pick.find(pick_id)
    pick.update!(status: :done)
    Notifier.send(pick)
    AuditLog.create!(pick: pick)
  end
end
```

After:
```ruby
# app/functions/foo_processor.rb
module FooProcessor
  class << self
    def run(pick)
      pick.update!(status: :done)
      Notifier.send(pick)
      AuditLog.create!(pick: pick)
    end
  end
end

class FooJob < ApplicationJob
  def perform(pick_id) = FooProcessor.run(Pick.find(pick_id))
end
```

테스트 시 Sidekiq 컨텍스트 없이 `FooProcessor`만 단위 테스트 가능 → 컨텍스트 세팅 비용 제거.

## 작업 워크플로우

1. **타깃 식별** — 클래스 파일 경로 확보. 명시되지 않았으면 묻는다.
2. **사용처 조사** (필수)
   - `graphify explain "ClassName"`으로 연결된 호출부를 파악하고, 누락이 없도록 `grep -rn "ClassName" app lib test`로 교차 확인
   - 호출부가 많아 PR이 비대해질 것 같으면 여러 PR로 단계적 마이그레이션. 단일 PR 안에서는 절대 절반만 바꾸지 않는다(8번 참조).
3. **판정 적용** — 메인 질문(객체 팩토리?) → No면 시나리오 1, Rails 프레임워크 클래스면 시나리오 2. 결과를 사용자에게 보여준다.
4. **테스트 우선** — 기존 테스트는 호출 형태만 바꾸고, 없으면 변환 전에 작성(RED).
5. **변환 적용** — 레시피 그대로.
6. **호출부 일괄 수정** — Step 2에서 모은 모든 호출부.
7. **검증**
   - `bin/rubocop <바뀐 파일들>` + `bundle exec srb tc`
   - 프로젝트의 테스트 명령으로 관련 디렉토리만 실행 (minitest면 `bin/rails test test/...`, RSpec이면 `bundle exec rspec spec/...` 등)
8. **이름 변경 시 일관성** — `Foo.new(x).call` → `Foo.build(x)`처럼 호출 형태가 바뀌면 별칭을 두지 말고 한 PR/커밋 안에서 모든 호출부를 일괄 변경.

## 안티패턴 — 하지 말 것

- **클래스를 모듈로 바꾸기만 하고 동일한 결합도 유지** — `extend self` + 인스턴스 변수 흉내. 의미가 없다.
- **프로젝트의 로깅 컨벤션 무시** — 로거 mixin이 있는데 신규 모듈만 `Rails.logger`를 직접 부르면 일관성이 깨진다.
- **순수 함수로 바꾸면서 사이드이펙트를 숨김** — `compute`가 DB를 쓰면 함수가 아니다. 이름이 거짓말을 한다.
- **`Data.define` 안에 비즈니스 로직 잔뜩 넣기** — 데이터 컨테이너의 본분을 넘으면 그건 다시 클래스다.
- **호출부의 절반만 새 API로 마이그레이션** — 같은 PR 안에서 일관성 깨진 채 커밋 금지.
- **Rails 프레임워크 클래스를 강제로 함수로 변환** — 시나리오 2(레시피 D)는 클래스 안의 본체만 옮긴다.

## 사용자에게 보고할 형식

리팩터링 제안 시 항상 아래 형식으로 답한다.

시나리오 1:
```
대상: app/services/xxx.rb

판정:
  메인 질문 — 객체 팩토리? No (호출부 N곳 모두 .new(...).call 1회)
  → 결정 트리:
    B. 모나드 파이프라인? No
    C. 데이터 버킷? No
    D. 단일 메서드 호출에만 인자 사용? Yes → 레시피 A

변환:
  - app/services/xxx.rb → app/functions/xxx.rb
  - 메서드명: call → <도메인 동사>
  - 호출부 N곳 수정 필요: <목록>

테스트: <기존 경로> → <함수 위치에 맞는 경로>
```

시나리오 2:
```
대상: app/jobs/xxx_job.rb (ApplicationJob 상속)

판정:
  적용 범위 예외 (Rails 프레임워크 클래스) → 시나리오 2, 레시피 D

변환:
  - 신규 app/functions/<도메인>/<함수>.rb 추출
  - 기존 Job: perform은 함수 위임 + 큐잉/스케줄링 책임만 유지
  - 호출부: 변경 없음 (Job 인터페이스 유지)
```

사용자 확인 후에만 실제 변경을 시작한다.
