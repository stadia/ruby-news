# frozen_string_literal: true

require_relative "../lib/quality/coverage_snapshot"
require "simplecov"
# 공용 설정은 프로젝트 루트의 `.simplecov`가 담당한다(자동 로드).
# 커버리지 시작은 .simplecov가 아닌 여기서 호출(SimpleCov 2.0 deprecation 대응).
SimpleCov.start "rails"
# command_name을 분리해 RSpec 결과와 병합되게 한다(서로 덮어쓰지 않음).
SimpleCov.command_name "Minitest"

SimpleCov.at_exit do
  result = SimpleCov.result
  result.format!
  Quality::CoverageSnapshot.persist_result!(result) if Quality::CoverageSnapshot.full_suite_run?
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require_relative "support/test_database_guard"
TestDatabaseGuard.acquire!(ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "primary").configuration_hash)
require "rails/test_help"
require "minitest/mock"

# 테스트 프로파일러. 계측은 전부 ENV 변수로만 켜지고, 변수가 없으면 아무것도
# 하지 않는다. 샘플링 프로파일러(TEST_VERNIER)는 이 require가
# `TestProf.activate` 훅으로 알아서 기동한다.
require "test-prof"

# EventProf/TagProf/MemoryProf/Sample은 test-prof가 싣는 minitest 플러그인이
# 담당한다. minitest 6.0이 `Minitest.run`에서 젬 자동 탐색(`load_plugins`)을
# 없앴으므로 명시적으로 등록해야 한다 -- Rails도 같은 이유로 "rails" 하나만
# 등록해 둔다.
Minitest.load "test_prof"

Warning[:deprecated] = true
module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Fedipub 엔진 픽스처 클래스 매핑 (테이블 이름에서 모델 클래스를 자동 감지할 수 없으므로)
    set_fixture_class fedipub_actors: Fedipub::Actor
    set_fixture_class fedipub_followings: Fedipub::Following

    def stub_constructor(klass, replacement)
      singleton_class = class << klass
        self
      end

      if singleton_class.instance_methods(false).include?(:new) || singleton_class.private_instance_methods(false).include?(:new)
        raise ArgumentError, "#{klass} defines its own .new; use klass.stub(:new, ...) instead"
      end

      singleton_class.define_method(:new) do |*args, **kwargs, &block|
        replacement.respond_to?(:call) ? replacement.call(*args, **kwargs, &block) : replacement
      end

      yield
    ensure
      singleton_class&.send(:remove_method, :new)
    end
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def sign_in_as(user)
    sign_in user
  end
end
