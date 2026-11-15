class AddEpisodeKeyToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :episode_key, :string, comment: "같은 에피소드를 다른 출처로 수집한 기사끼리 공유하는 키(예: on_rails:20121188)"
    add_index :articles, :episode_key, where: "episode_key IS NOT NULL"
  end
end
