import { Controller } from "@hotwired/stimulus"

// 저장하지 못한 선택은 전체 새로고침 전까지 Turbo 이동 사이에 유지한다.
let memoryTheme = null

export default class extends Controller {
  initialize() {
    this.setTheme()
  }

  setTheme({ disableTransitions = false, storedTheme } = {}) {
    if (disableTransitions) this.disableTransitionsForThemeChange()

    if (storedTheme === undefined) {
      try {
        storedTheme = memoryTheme ?? localStorage.theme
      } catch {
        storedTheme = memoryTheme
      }
    }
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
    const dark = storedTheme === 'dark' || (storedTheme !== 'light' && prefersDark)
    document.documentElement.classList.toggle('dark', dark)
    document.documentElement.classList.toggle('light', !dark)
    document.documentElement.classList.toggle('theme-dark', dark)
    document.documentElement.classList.toggle('theme-light', !dark)
    this.syncThemeColor(storedTheme)
  }

  // head의 theme-color 메타는 OS 테마(media)로 갈린다. 사용자가 테마를 직접
  // 골랐으면 그 테마의 메타만 적용되게 media를 덮어쓴다.
  syncThemeColor(storedTheme) {
    document.querySelectorAll('meta[name="theme-color"][data-theme]').forEach((meta) => {
      const theme = meta.dataset.theme
      if (storedTheme !== 'light' && storedTheme !== 'dark') {
        meta.media = `(prefers-color-scheme: ${theme})`
      } else {
        meta.media = theme === storedTheme ? 'all' : 'not all'
      }
    })
  }

  setLightTheme() {
    // Whenever the user explicitly chooses light mode
    try {
      localStorage.theme = 'light'
      memoryTheme = null
    } catch {
      memoryTheme = 'light'
    }
    this.setTheme({ disableTransitions: true, storedTheme: 'light' })
  }

  setDarkTheme() {
    // Whenever the user explicitly chooses dark mode
    try {
      localStorage.theme = 'dark'
      memoryTheme = null
    } catch {
      memoryTheme = 'dark'
    }
    this.setTheme({ disableTransitions: true, storedTheme: 'dark' })
  }

  disableTransitionsForThemeChange() {
    document.documentElement.classList.add('theme-transition-disabled')
    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => {
        document.documentElement.classList.remove('theme-transition-disabled')
      })
    })
  }
}
