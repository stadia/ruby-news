# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# One editorial correction for the Japanese article detail, kept separate from
# the generated summaries. See the upstream sources linked in BODY.
module SolidCableJapaneseCorrection
  HOST = "ruby-news.jp"
  SLUG = "rails-8-solidcable-database-backed-websockets-guide"
  KEY_POINTS = [
    "Solid Cableはメッセージをデータベースのテーブルに保存し、PostgreSQLを使う場合もポーリングで配信します。",
    "LISTEN/NOTIFYを使うのは、Solid Cableとは別のAction Cable標準のPostgreSQLアダプターです。",
    "既定の100msはポーリング間隔です。実際の配信時間やデータベースへの負荷は、アプリケーションの構成や負荷によって変わります。"
  ].freeze
  INTRODUCTION = "Rails 8の新規アプリでは、Solid Cableが本番用のAction Cableアダプターとして設定されます。WebSocket配信にRedisを使わない構成を選べます。"
  BODY = <<~MARKDOWN
    ### Solid CableとPostgreSQLアダプターの違い

    `adapter: solid_cable`はメッセージをテーブルに保存します。Action Cableサーバー側のリスナーが購読中のチャンネルの新着をまとめて確認し、クライアントへ配信します。各WebSocket接続が個別にデータベースをポーリングするわけではありません。

    PostgreSQLをストレージに選んでも、Solid Cableの配信方式はポーリングです。一方、`adapter: postgresql`はAction Cableに組み込まれた別のアダプターで、`LISTEN/NOTIFY`を使います。こちらを選ぶ場合は通知ペイロードのサイズ制限も確認してください。

    ### 100msをどう読むか

    `config/cable.yml`の`polling_interval`の既定値は0.1秒ですが、伝達遅延の上限ではありません。実際の配信には、次のポーリングを待つ時間に加えて、書き込み、クエリ、クライアントへの送信にかかる時間も影響します。間隔を短くする前に、想定負荷での配信遅延とデータベースの負荷を測ってください。

    ### 既存アプリに追加する場合

    `bin/rails solid_cable:install`は`config/cable.yml`を更新し、専用データベース用のスキーマを作成します。既存の設定との差分を確認し、`connects_to`の接続名を`config/database.yml`と揃えてから`bin/rails db:prepare`を実行します。単一データベースを使う場合は手順が異なります。

    詳細は[Solid Cable公式README](https://github.com/rails/solid_cable#readme)と[Action Cableガイド](https://guides.rubyonrails.org/action_cable_overview.html#postgresql-adapter)を参照してください。
  MARKDOWN
  CONCLUSION = "すでに利用しているデータベースに配信をまとめたい場合はSolid Cableが候補です。遅延の要件が厳しい場合は、設定値ではなく実測の配信時間で判断してください。"
end
