# typed: strong

# `Data.define` 값 객체의 멤버 타입 선언.
#
# Sorbet은 `Data.define`이 만드는 클래스(생성자·멤버 리더·members)까지는 합성하지만
# 멤버의 타입은 모르고 전부 untyped로 둔다. 그 타입을 여기에서 좁힌다.
# 멤버를 추가하거나 타입을 바꾸면 이 파일도 함께 고쳐야 한다.
#
# 소스 쪽 `Data.define`에는 심볼만 넘긴다. 인자 줄에 `#: String`을 다는 rbs-inline
# 표기를 쓰면 Sorbet이 그 주석을 멤버 선언이 아니라 심볼 리터럴에 대한 타입 단언으로
# 읽어 `srb tc`가 깨진다. 배경과 대가는 AGENTS.md 참고.

module SitemapBuilder
  class Entry
    sig { returns(String) }
    def path; end

    sig { returns(T.nilable(String)) }
    def lastmod; end

    sig { returns(T::Array[String]) }
    def available; end
  end
end

module Articles
  module ItemListSchema
    class Payload
      sig { returns(String) }
      def name; end

      sig { returns(T::Array[String]) }
      def urls; end
    end
  end

  module Search
    class IndexResult
      sig { returns(Pagy) }
      def pagy; end

      sig { returns(T::Array[Article]) }
      def articles; end

      sig { returns(T::Array[String]) }
      def suggestions; end
    end
  end
end

module HumanizeKoreanGoldenChecks
  class Failure
    sig { returns(String) }
    def code; end

    sig { returns(String) }
    def message; end
  end
end

module Quality
  module TestProfileReport
    class Section
      sig { returns(String) }
      def title; end

      sig { returns(String) }
      def body; end
    end
  end

  class Report
    class GateResult
      sig { returns(String) }
      def name; end

      sig { returns(T.nilable(Numeric)) }
      def measure; end

      sig { returns(T.nilable(Numeric)) }
      def threshold; end

      sig { returns(T::Boolean) }
      def passed; end

      sig { returns(String) }
      def unit; end

      sig { returns(Symbol) }
      def cmp; end
    end
  end
end

module OauthAccounts
  module Callbacks
    class SignIn
      sig { returns(User) }
      def user; end
    end

    class CompleteSignup
      sig { returns(T::Hash[String, T.untyped]) }
      def signup_payload; end
    end
  end

  module Registration
    class Result
      sig { returns(T::Boolean) }
      def success; end

      sig { returns(User) }
      def user; end
    end
  end
end
