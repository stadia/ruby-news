# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# 블로그 글 제목을 공개 URL(/@:username/blog/:slug)용 slug로 정규화한다.
#
# FriendlyId 기본 정규화(`parameterize`)는 ASCII로 음역하면서 한글을 모두 지우므로
# 쓰지 않는다. 글자(\p{L})·결합 문자(\p{M})·숫자(\p{N})만 남기고 나머지 연속은
# 하이픈 하나로 바꾼다. `/ . ? # %`처럼 경로를 깨는 문자는 모두 여기서 빠지고,
# 한글은 URL 헬퍼가 퍼센트 인코딩한다.
module BlogSlug
  # 제목에서 온 부분의 최대 글자 수. 한글 한 글자는 퍼센트 인코딩 후 9바이트다.
  BASE_MAX_LENGTH = 80
  # 같은 slug가 이미 있을 때 붙이는 무작위 접미사 길이.
  SUFFIX_LENGTH = 8
  # slug 전체 최대 길이(제목 부분 + "-" + 접미사). FriendlyId의 생성 제한이며 text 컬럼과 모델 검증은 길이를 제한하지 않는다.
  MAX_LENGTH = BASE_MAX_LENGTH + 1 + SUFFIX_LENGTH

  class << self
    # 유효한 문자가 없으면 빈 문자열을 돌려준다. 멱등이다.
    #: (String? title) -> String
    def normalize(title)
      title.to_s.unicode_normalize(:nfc).downcase
        .gsub(/(?:[\p{L}\p{N}]\p{M}*)|./m) { |part| part.match?(/\A[\p{L}\p{N}]/) ? part : "-" }
        .gsub(/-+/, "-")
        .delete_prefix("-")[0, BASE_MAX_LENGTH].to_s
        .delete_suffix("-")
    end

    #: (String base) -> String
    def with_suffix(base)
      "#{base}-#{SecureRandom.alphanumeric(SUFFIX_LENGTH).downcase}"
    end
  end
end
