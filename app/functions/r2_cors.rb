# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# 블로그 에디터(Lexxy)의 이미지 업로드는 ActiveStorage direct upload라서 브라우저가
# 파일을 R2 버킷에 직접 PUT한다. 버킷에 CORS 규칙이 없으면 이 PUT의 preflight(OPTIONS)가
# 403 "CORS not configured for this bucket"으로 막혀 업로드가 실패한다.
#
# 버킷 설정은 배포로 바뀌지 않으므로 `bin/rails active_storage:r2_cors`로 한 번 넣는다.
# 규칙은 이 모듈 한 곳에서 만들고, 허용 헤더는 S3Service#headers_for_direct_upload가
# 싣는 헤더와 테스트로 맞춰 둔다.
module R2Cors
  ALLOWED_METHODS = %w[PUT].freeze
  # S3Service#headers_for_direct_upload가 PUT에 싣는 헤더.
  ALLOWED_HEADERS = %w[Content-Type Content-MD5 Content-Disposition].freeze
  MAX_AGE_SECONDS = 3600

  class << self
    # 에디터를 여는 사이트(Hosts::FOR_LOCALE의 .dev/.jp)에
    # ACTIVE_STORAGE_CORS_ORIGINS(쉼표 구분, 스테이징 등)를 더한다.
    #: () -> Array[String]
    def origins
      extra = ENV.fetch("ACTIVE_STORAGE_CORS_ORIGINS", "").split(",").map(&:strip).reject(&:empty?)
      (Hosts::FOR_LOCALE.values + extra).uniq
    end

    #: (?Array[String]) -> Hash[Symbol, untyped]
    def configuration(allowed_origins = origins)
      {
        cors_rules: [
          {
            allowed_origins: allowed_origins,
            allowed_methods: ALLOWED_METHODS,
            allowed_headers: ALLOWED_HEADERS,
            max_age_seconds: MAX_AGE_SECONDS
          }
        ]
      }
    end

    # 버킷에 지금 걸린 CORS 규칙. 설정이 없으면 빈 배열.
    #: (ActiveStorage::Service::S3Service) -> Array[untyped]
    def current_rules(service)
      service.bucket.client.get_bucket_cors(bucket: service.bucket.name).cors_rules.map(&:to_h)
    rescue Aws::Errors::ServiceError => e
      raise unless e.code == "NoSuchCORSConfiguration"

      []
    end

    # 버킷의 CORS 규칙을 configuration으로 바꾼다(PutBucketCors는 전체 교체).
    #: (ActiveStorage::Service::S3Service, ?Array[String]) -> void
    def apply!(service, allowed_origins = origins)
      service.bucket.client.put_bucket_cors(bucket: service.bucket.name, cors_configuration: configuration(allowed_origins))
    end
  end
end
