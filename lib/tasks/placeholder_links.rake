# typed: false
# frozen_string_literal: true
# rbs_inline: enabled

namespace :articles do
  desc "요약 본문의 example.com 자리표시자 링크를 고친다(#1161). 기본은 드라이런, WRITE=true일 때만 저장"
  task repair_placeholder_links: :environment do
    write = ActiveModel::Type::Boolean.new.cast(ENV["WRITE"]) || false
    changes = Articles::PlaceholderLinks.repair_all(write:)

    changes.each do |change|
      removed = change.before.scan(/[^\n]*example\.(?:com|org|net)[^\n]*/) - change.after.lines.map(&:chomp)
      puts "##{change.article_id} #{change.slug} #{change.attribute}"
      removed.each { puts "  - #{it.strip}" }
    end
    puts "#{write ? '수정' : '[DRY_RUN] 수정 예정'}: 기사 #{changes.map(&:article_id).uniq.size}건, 필드 #{changes.size}개"
  end
end
