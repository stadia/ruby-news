# frozen_string_literal: true

# posts.slug·articles.slug를 text로 바꾼다(#1012).
#
# 블로그 글이 제목에서 slug를 만들면서 posts.slug varchar(22)가 모자라게 됐다.
# 길이 상한은 DB가 아니라 BlogSlug(제목 80자 + "-" + 접미사 8자)가 정한다.
# articles.slug도 같은 성격의 URL 식별자라 함께 text로 맞춘다.
#
# varchar → text는 PostgreSQL에서 바이너리 호환이라 테이블 재작성은 필요 없다.
# 전체 유니크 인덱스는 재사용될 수 있지만 articles의 부분 인덱스는 재생성된다.
# ALTER TABLE의 ACCESS EXCLUSIVE 잠금과 부분 인덱스 재생성 비용을 배포 시 고려한다.
class ChangeSlugColumnsToText < ActiveRecord::Migration[8.1]
  def up
    change_column :posts, :slug, :text
    change_column :articles, :slug, :text
  end

  # posts.slug는 22자를 넘는 값이 있으면 PostgreSQL이 절단 대신 오류를 내므로,
  # 되돌리기 전에 제목 기반 slug와 UUID 폴백 slug를 정리해야 한다.
  # 이전 마이그레이션(AddSlugToPosts)의 실제 정의는 varchar(22)다.
  def down
    change_column :articles, :slug, :string
    change_column :posts, :slug, :string, limit: 22
  end
end
