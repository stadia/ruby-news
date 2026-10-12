# frozen_string_literal: true

# 윤문(HumanMonolithAgent) 결과를 기사에 남긴다(#1098).
#
# 윤문은 원 요약 뒤에 도는 보조 단계라 실패해도 파이프라인이 계속되고, 결과가 로그에만
# 남아 반영되지 않은 기사를 조회할 수 없었다. 결과·사유·빠진 필드·시각을 한 JSONB에 담는다.
# 모양은 ArticleHumanizer.status / failed_status가 정한다. 기존 기사는 NULL(기록 없음)이다.
#
# nullable 컬럼 추가는 기본값이 없어 테이블 재작성 없이 끝난다.
class AddHumanizeStatusToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :humanize_status, :jsonb, comment: "윤문 결과(outcome·reason·dropped·error·at)"
  end
end
