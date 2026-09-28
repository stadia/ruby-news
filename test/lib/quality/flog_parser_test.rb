# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../../lib/quality/flog_parser"

module Quality
  class FlogParserTest < ActiveSupport::TestCase
    test "독립 스킬 스크립트는 디렉터리 입력에서도 복잡도 측정에서 제외한다" do
      Dir.mktmpdir do |directory|
        path = write_method(directory, "app/skills/demo/scripts/run.rb")

        assert_equal({ method_max: 0.0, class_max: 0.0 }, FlogParser.new(File.dirname(path)).parse)
      end
    end

    test "독립 스킬 스크립트는 명시적 파일 입력에서도 제외한다" do
      Dir.mktmpdir do |directory|
        path = write_method(directory, "app/skills/demo/scripts/run.rb")

        assert_equal({ method_max: 0.0, class_max: 0.0 }, FlogParser.new(path).parse)
      end
    end

    test "뷰와 컴포넌트의 기존 제외 범위를 유지한다" do
      Dir.mktmpdir do |directory|
        paths = %w[app/views/demo.rb app/components/demo.rb].map { |path| write_method(directory, path) }

        assert_equal({ method_max: 0.0, class_max: 0.0 }, FlogParser.new(paths).parse)
      end
    end

    test "앱과 품질 도구의 런타임 코드는 계속 측정한다" do
      Dir.mktmpdir do |directory|
        %w[app/services/demo.rb app/functions/demo.rb lib/quality/demo.rb].each do |relative_path|
          path = write_method(directory, relative_path)
          result = FlogParser.new(path).parse

          assert_operator result[:method_max], :>, 0
          assert_equal result[:method_max], result[:class_max]
        end
      end
    end

    private

    def write_method(directory, relative_path)
      path = File.join(directory, relative_path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "class Demo\n  def run(value)\n    value.to_s.strip\n  end\nend\n")
      path
    end
  end
end
