# typed: true
# frozen_string_literal: true
# rbs_inline: enabled

# gpt-image 계열은 채팅이 아니라 이미지 엔드포인트(RubyLLM.paint)로만 생성되므로
# RubyLLM::Agent 대신 지침을 프롬프트에 합쳐 paint를 호출한다.
module ArticleImageAgent
  MODEL = "openai/gpt-image-2"
  PROVIDER = :openrouter

  INSTRUCTIONS = <<~PROMPT
    - 16:9 비율의 가로형 이미지로 생성한다.
    - 클리셰(악수, 휴머노이드 로봇, 회로 기판/PCB 트레이스 패턴 배경 등)와 사실적 인체 묘사는 피한다. 특히 회로 기판 모티브는 기술 기사 섬네일에서 과사용되므로 배경/장식 요소로 쓰지 않는다.
    - 이미지 내 텍스트는 가급적 한국어/일본어가 아닌 영어를 사용한다.
    - 색상은 60:30:10 법칙을 따른다: 화면을 칠하는 색의 면적을 기준으로 지배 색상이 약 60%, 보조 색상이 약 30%, 시선을 끄는 포인트(accent) 색상이 약 10%를 차지하도록 조화롭게 배치한다. 이는 색을 칠하는 면적 비율에 대한 지시일 뿐이며, "60:30:10"이나 60/30/10 같은 수치·퍼센트·비율 표기를 이미지 안에 글자나 숫자로 그려 넣지 않는다.
  PROMPT

  class << self
    # OpenRouter 이미지 API는 size를 무시하고 aspect_ratio provider 옵션을 받는다.
    #: (String prompt) -> RubyLLM::Image
    def paint(prompt)
      RubyLLM.paint(
        "#{prompt}\n\n[지침]\n#{INSTRUCTIONS}",
        model: MODEL,
        provider: PROVIDER,
        provider_options: { aspect_ratio: "16:9" }
      )
    end
  end
end
