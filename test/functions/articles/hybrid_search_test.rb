# frozen_string_literal: true

require "test_helper"

class Articles::HybridSearchTest < ActiveSupport::TestCase
  EmbedResult = Struct.new(:vectors)

  setup do
    # Ensure pg_search_document tsvector is populated for FTS tests
    ActiveRecord::Base.connection.execute(
      "UPDATE pg_search_documents SET tsvector_content_tsearch = " \
      "to_tsvector('english', coalesce(content, '')) WHERE searchable_type = 'Article'"
    )
    # Use a real memory cache so embedding cache tests work (test env uses :null_store)
    @_original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @_original_cache
  end

  def stub_embed(vector)
    RubyLLM.stub(:embed, EmbedResult.new(vector)) { yield }
  end

  test "blank query returns empty array" do
    assert_equal [], Articles::HybridSearch.run(query: "")
    assert_equal [], Articles::HybridSearch.run(query: "   ")
  end

  test "falls back to FTS-only ids when embedding fails" do
    RubyLLM.stub(:embed, ->(*) { raise StandardError, "api down" }) do
      ids = Articles::HybridSearch.run(query: "Ruby")

      assert_includes ids, articles(:ruby_article).id
    end
  end

  test "returns FTS matches when embedding succeeds but no article embeddings exist" do
    Rails.cache.clear
    stub_embed(Array.new(Articles::HybridSearch::EMBED_DIMENSIONS, 0.0).tap { |v| v[0] = 1.0 }) do
      ids = Articles::HybridSearch.run(query: "Ruby")

      assert_includes ids, articles(:ruby_article).id
    end
  end

  test "vector-matched article surfaces via embedding similarity" do
    Rails.cache.clear
    target = articles(:ruby_article)
    qvec = Array.new(Articles::HybridSearch::EMBED_DIMENSIONS, 0.0)
    qvec[0] = 1.0
    target.update_column(:embedding, qvec)

    stub_embed(qvec) do
      ids = Articles::HybridSearch.run(query: "zzznontextmatch")

      assert_includes ids, target.id
    end
  end

  test "caches the query embedding across calls" do
    Rails.cache.clear
    calls = 0
    embed = lambda do |*|
      calls += 1
      EmbedResult.new(Array.new(Articles::HybridSearch::EMBED_DIMENSIONS, 0.0).tap { |v| v[0] = 1.0 })
    end
    RubyLLM.stub(:embed, embed) do
      Articles::HybridSearch.run(query: "CacheTerm")
      Articles::HybridSearch.run(query: "CacheTerm")
    end

    assert_equal 1, calls
  end

  test "excludes vector-only candidate below cosine threshold while keeping aligned one" do
    Rails.cache.clear
    qvec = Array.new(Articles::HybridSearch::EMBED_DIMENSIONS, 0.0)
    qvec[0] = 1.0

    aligned = articles(:ruby_article)
    aligned.update_column(:embedding, qvec)

    orthogonal_vec = Array.new(Articles::HybridSearch::EMBED_DIMENSIONS, 0.0)
    orthogonal_vec[1] = 1.0
    orthogonal = articles(:korean_content_article)
    orthogonal.update_column(:embedding, orthogonal_vec)

    # Query term does not FTS-match either article, so survival depends on cosine threshold.
    stub_embed(qvec) do
      ids = Articles::HybridSearch.run(query: "zzznontextmatch")

      assert_includes ids, aligned.id
      assert_not_includes ids, orthogonal.id
    end
  end

  def capture_sql(&block)
    sqls = []
    callback = ->(*, payload) { sqls << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
    sqls
  end

  test "widens HNSW search so filtered vector candidates fill the pool" do
    Rails.cache.clear
    qvec = Array.new(Articles::HybridSearch::EMBED_DIMENSIONS, 0.0).tap { |v| v[0] = 1.0 }

    sqls = stub_embed(qvec) { capture_sql { Articles::HybridSearch.run(query: "Ruby") } }

    assert sqls.any? { |s| s.include?("hnsw.ef_search") }
    assert sqls.any? { |s| s.include?("hnsw.iterative_scan") }
  end

  test "threshold filter reuses vector distances instead of reloading embeddings" do
    Rails.cache.clear
    qvec = Array.new(Articles::HybridSearch::EMBED_DIMENSIONS, 0.0).tap { |v| v[0] = 1.0 }
    articles(:ruby_article).update_column(:embedding, qvec)

    sqls = stub_embed(qvec) { capture_sql { Articles::HybridSearch.run(query: "zzznontextmatch") } }

    assert_not sqls.any? { |s| s.include?(%("articles"."embedding" FROM)) }
  end

  test "mmr reranking path returns aligned article without error" do
    Rails.cache.clear
    qvec = Array.new(Articles::HybridSearch::EMBED_DIMENSIONS, 0.0)
    qvec[0] = 1.0

    target = articles(:ruby_article)
    target.update_column(:embedding, qvec)

    stub_embed(qvec) do
      ids = Articles::HybridSearch.run(query: "Ruby", mmr: true)

      assert_includes ids, target.id
    end
  end
end
