// FacetX note preview: a read-only markdown renderer (markdown-it) with KaTeX
// math, hosted in a WKWebView. The native side owns editing; this view only
// displays the rendered markdown it is given. The same bundle also backs the
// compact "chat" variant used for assistant message bubbles.
//
// Native ↔ JS contract:
//   • Native → JS: window.FacetXPreview.setContent(markdown, variant), .setTheme('light'|'dark')
//   • JS → Native: window.webkit.messageHandlers.facetx.postMessage({ type: 'ready' })
//                  window.webkit.messageHandlers.facetx.postMessage({ type: 'height', value })

import MarkdownIt from 'markdown-it'
import katexPluginNS from '@vscode/markdown-it-katex'

import 'katex/dist/katex.min.css'
import './theme.css'

// The plugin's callable lives at different depths depending on interop; unwrap it.
const katexPlugin =
  typeof katexPluginNS === 'function'
    ? katexPluginNS
    : katexPluginNS?.default?.default ?? katexPluginNS?.default ?? katexPluginNS

const md = new MarkdownIt({
  html: false, // escape raw HTML — preview content is untrusted markdown
  linkify: true,
  typographer: true,
  breaks: false,
})
md.use(katexPlugin)

const root = document.getElementById('content')

function postToNative(message) {
  try {
    window.webkit?.messageHandlers?.facetx?.postMessage(message)
  } catch (_) {
    /* running outside the WKWebView host — ignore */
  }
}

let lastReportedHeight = -1

function reportHeight() {
  const height = Math.ceil(root.getBoundingClientRect().height)
  if (height === lastReportedHeight) return
  lastReportedHeight = height
  postToNative({ type: 'height', value: height })
}

// KaTeX/font loading and image decodes can change layout after the initial
// render, so keep watching rather than measuring once synchronously.
new ResizeObserver(reportHeight).observe(root)

function render(markdown, variant) {
  const extraClasses = variant && variant !== 'note' ? ` ${variant}` : ''
  root.className = `markdown-body${extraClasses}`
  root.innerHTML = md.render(markdown ?? '')
  reportHeight()
}

// Streamed assistant replies call setContent on every delta (potentially many
// times a second). Re-parsing markdown is cheap, but coalescing to one
// render per animation frame avoids flooding the WKWebView bridge with calls
// that would only ever be superseded by the next one anyway.
let pendingRender = null
let renderScheduled = false

function scheduleRender(markdown, variant) {
  pendingRender = { markdown, variant }
  if (renderScheduled) return
  renderScheduled = true
  requestAnimationFrame(() => {
    renderScheduled = false
    const next = pendingRender
    pendingRender = null
    render(next.markdown, next.variant)
  })
}

window.FacetXPreview = {
  setContent(markdown, variant) {
    scheduleRender(markdown, variant)
  },
  setTheme(mode) {
    document.documentElement.dataset.theme = mode === 'dark' ? 'dark' : 'light'
  },
  setFullWidth(enabled) {
    root.classList.toggle('full-width', !!enabled)
  },
}

postToNative({ type: 'ready' })
