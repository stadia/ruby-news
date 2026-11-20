# R2 버킷 CORS 설정 (에디터 이미지 업로드)

## 왜 필요한가

블로그 에디터(Lexxy)의 이미지 업로드는 ActiveStorage direct upload를 씁니다.

1. 브라우저가 `POST /rails/active_storage/direct_uploads`로 blob을 만들고, 서명된 R2 업로드 URL을 받습니다.
2. 브라우저가 그 URL(`https://<account>.r2.cloudflarestorage.com/<bucket>/<key>`)에 파일을 **직접 PUT**합니다.

2번은 다른 출처로 보내는 요청이라, 버킷에 CORS 규칙이 있어야 합니다. 규칙이 없으면 브라우저의 preflight(OPTIONS)가 다음처럼 거절되고, 에디터에는 업로드 실패만 보입니다.

```
HTTP/1.1 403 Forbidden
<Error><Code>Unauthorized</Code><Message>CORS not configured for this bucket</Message></Error>
```

버킷 설정이라 코드 배포로는 바뀌지 않습니다. 버킷마다 한 번 넣어야 합니다.

## 넣는 규칙

`R2Cors.configuration`(`app/functions/r2_cors.rb`)이 만듭니다.

| 항목 | 값 |
|---|---|
| AllowedOrigins | `https://ruby-news.dev`, `https://ruby-news.jp` (`Hosts::FOR_LOCALE`) + `ACTIVE_STORAGE_CORS_ORIGINS`(쉼표 구분) |
| AllowedMethods | `PUT` |
| AllowedHeaders | `Content-Type`, `Content-MD5`, `Content-Disposition` (`S3Service#headers_for_direct_upload`가 싣는 헤더) |
| MaxAgeSeconds | `3600` |

이미지 조회는 CDN(`ACTIVE_STORAGE_CDN_HOST`)이나 blob 리다이렉트로 하므로 GET은 넣지 않았습니다.

## 적용

운영 컨테이너에서 실행합니다. 앱이 쓰는 R2 키(`R2_ACCESS_KEY_ID`/`R2_SECRET_ACCESS_KEY`)로 호출합니다.

```sh
# 현재 규칙과 넣을 규칙만 출력
kubectl exec deploy/ruby-news-web -n default -- env DRY_RUN=true bin/rails active_storage:r2_cors

# 적용 (PutBucketCors는 버킷의 CORS 규칙 전체를 교체한다)
kubectl exec deploy/ruby-news-web -n default -- bin/rails active_storage:r2_cors
```

앱의 R2 API 토큰이 "Object Read & Write" 권한만 있으면 버킷 설정을 바꿀 수 없어 `AccessDenied`가 납니다. 이 경우 "Admin Read & Write" 토큰으로 실행하거나, Cloudflare 대시보드(R2 → 버킷 → Settings → CORS Policy)에 아래 JSON을 넣습니다.

```json
[
  {
    "AllowedOrigins": ["https://ruby-news.dev", "https://ruby-news.jp"],
    "AllowedMethods": ["PUT"],
    "AllowedHeaders": ["Content-Type", "Content-MD5", "Content-Disposition"],
    "MaxAgeSeconds": 3600
  }
]
```

## 확인

preflight가 200이고 `Access-Control-Allow-Origin`이 오면 됩니다.

```sh
curl -s -i -X OPTIONS "https://<account>.r2.cloudflarestorage.com/<bucket>/probe" \
  -H "Origin: https://ruby-news.dev" \
  -H "Access-Control-Request-Method: PUT" \
  -H "Access-Control-Request-Headers: content-type,content-md5,content-disposition" | head -5
```

그다음 블로그 에디터에서 이미지 버튼으로 사진을 올려, 본문에 사진이 들어가는지 봅니다.
