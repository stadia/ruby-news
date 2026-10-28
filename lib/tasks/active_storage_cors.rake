# typed: false
# frozen_string_literal: true
# rbs_inline: enabled

namespace :active_storage do
  desc "R2 버킷에 direct upload용 CORS 규칙을 넣는다(블로그 에디터 이미지 업로드). " \
       "옵션: DRY_RUN=true SERVICE=cloudflare ACTIVE_STORAGE_CORS_ORIGINS=https://a,https://b"
  task r2_cors: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
    service_name = (ENV["SERVICE"].presence || "cloudflare").to_sym
    service = ActiveStorage::Blob.services.fetch(service_name)

    unless service.is_a?(ActiveStorage::Service::S3Service)
      abort "#{service_name} 서비스는 S3 호환이 아니다(#{service.class}). SERVICE=로 R2 서비스를 지정한다."
    end

    puts "버킷: #{service.bucket.name} (#{service_name})"
    puts "현재 규칙: #{R2Cors.current_rules(service).to_json}"
    puts "넣을 규칙: #{R2Cors.configuration[:cors_rules].to_json}"

    if dry_run
      puts "[DRY_RUN] 적용 생략"
      next
    end

    R2Cors.apply!(service)
    puts "적용 후: #{R2Cors.current_rules(service).to_json}"
  end
end
