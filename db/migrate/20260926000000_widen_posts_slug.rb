# frozen_string_literal: true

# 블로그 글이 제목에서 slug를 만들도록(#1012) posts.slug를 22자에서 넓힌다.
# 길이는 BlogSlug::MAX_LENGTH(제목 80자 + "-" + 접미사 8자)와 같다. 마이그레이션은
# 앱 상수에 기대지 않도록 값을 그대로 적는다. 기존 무작위 slug와 유니크 인덱스는
# 그대로 둔다.
class WidenPostsSlug < ActiveRecord::Migration[8.1]
  def up
    change_column :posts, :slug, :string, limit: 89
  end

  # 22자를 넘는 slug가 있으면 PostgreSQL이 절단 대신 오류를 내므로, 되돌리기 전에
  # 제목 기반 slug를 정리해야 한다.
  def down
    change_column :posts, :slug, :string, limit: 22
  end
end
