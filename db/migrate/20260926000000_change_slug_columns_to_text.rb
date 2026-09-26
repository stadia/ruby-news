# frozen_string_literal: true

# posts.slug·articles.slug를 text로 바꾼다(#1012).
#
# 블로그 글이 제목에서 slug를 만들면서 posts.slug varchar(22)가 모자라게 됐다.
# 길이 상한은 DB가 아니라 BlogSlug(제목 80자 + "-" + 접미사 8자)가 정한다.
# articles.slug도 같은 성격의 URL 식별자라 함께 text로 맞춘다.
#
# varchar → text는 PostgreSQL에서 바이너리 호환이라 테이블 재작성이나 인덱스
# 재생성 없이 끝난다. 유니크 인덱스(부분 인덱스 포함)는 그대로 유지된다.
class ChangeSlugColumnsToText < ActiveRecord::Migration[8.1]
  def up
    change_column :posts, :slug, :text
    change_column :articles, :slug, :text
  end

  # posts.slug는 22자를 넘는 값이 있으면 PostgreSQL이 절단 대신 오류를 내므로,
  # 되돌리기 전에 제목 기반 slug를 정리해야 한다.
  def down
    change_column :articles, :slug, :string
    change_column :posts, :slug, :string, limit: 22
  end
end
