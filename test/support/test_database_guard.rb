# typed: false
# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"

# 같은 호스트의 다른 worktree/runner도 같은 PostgreSQL DB의 fixture 작업을 배타적으로 실행한다.
module TestDatabaseGuard
  class << self
    def acquire!(configuration)
      host = configuration[:host].to_s
      host = "localhost" if host.empty?
      port = Integer(configuration[:port] || 5432)
      identity = Digest::SHA256.hexdigest([ host, port, configuration.fetch(:database) ].join("\0"))
      @locks ||= {}
      return if @locks.key?(identity)

      directory = File.join(Dir.tmpdir, "al_news-test-database-locks")
      FileUtils.mkdir_p(directory, mode: 0o700)
      lock = File.open(File.join(directory, "#{identity}.lock"), File::WRONLY | File::CREAT, 0o600)
      unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        lock.close
        # 부팅 중단 결과가 기존 커버리지 및 full-suite snapshot을 덮지 않도록 한다.
        SimpleCov.at_exit { } if defined?(SimpleCov)
        abort "같은 테스트 DB를 다른 테스트 프로세스가 사용하고 있습니다. 기존 실행이 끝난 뒤 다시 실행하거나, 실행마다 서로 다른 TEST_DATABASE_URL을 지정하세요."
      end

      # 파일을 지우면 대기 중인 프로세스와 inode가 달라지므로 유지한다.
      # 파일 핸들은 실행 종료까지 보관하고 잠금 해제는 OS에 맡긴다.
      @locks[identity] = lock
    end
  end
end
