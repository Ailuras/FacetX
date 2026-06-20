// FacetX note preview: a read-only markdown renderer (markdown-it) with KaTeX
// math, hosted in a WKWebView. The native side owns editing; this view only
// displays the rendered markdown it is given.
//
// Native ↔ JS contract:
//   • Native → JS: window.FacetXPreview.setContent(markdown), .setTheme('light'|'dark')
//   • JS → Native: window.webkit.messageHandlers.facetx.postMessage({ type: 'ready' })

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

function render(markdown) {
  root.innerHTML = md.render(markdown ?? '')
}

window.FacetXPreview = {
  setContent(markdown) {
    render(markdown)
  },
  setTheme(mode) {
    document.documentElement.dataset.theme = mode === 'dark' ? 'dark' : 'light'
  },
}

function postToNative(message) {
  try {
    window.webkit?.messageHandlers?.facetx?.postMessage(message)
  } catch (_) {
    /* running outside the WKWebView host — ignore */
  }
}

postToNative({ type: 'ready' })
