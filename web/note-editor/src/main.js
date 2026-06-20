// FacetX note editor: a Milkdown (Crepe) WYSIWYG markdown editor with KaTeX math,
// hosted in a WKWebView. Markdown is the source of truth — it is loaded from and
// written back to the native side, which persists the project's `.md` file.
//
// Native ↔ JS contract:
//   • Native → JS: window.FacetXEditor.setContent(markdown), .setReadonly(bool),
//                   .setTheme('light' | 'dark')
//   • JS → Native: window.webkit.messageHandlers.facetx.postMessage({...})
//       { type: 'ready' }                       editor mounted, send content
//       { type: 'change', markdown: string }    debounced content change

import { Crepe } from '@milkdown/crepe'

import '@milkdown/crepe/theme/common/style.css'
import '@milkdown/crepe/theme/nord.css'
import 'katex/dist/katex.min.css'
import './theme.css'

const root = document.getElementById('app')

let crepe = null
let suppressChange = false // ignore the change event caused by programmatic loads
let debounceTimer = null

function postToNative(message) {
  try {
    window.webkit?.messageHandlers?.facetx?.postMessage(message)
  } catch (_) {
    /* running outside the WKWebView host (e.g. a browser) — ignore */
  }
}

function scheduleChange(markdown) {
  if (suppressChange) return
  clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => {
    postToNative({ type: 'change', markdown })
  }, 400)
}

async function buildEditor(initialMarkdown) {
  crepe = new Crepe({
    root,
    defaultValue: initialMarkdown ?? '',
    features: {
      [Crepe.Feature.Latex]: true,
      [Crepe.Feature.CodeMirror]: true,
      [Crepe.Feature.ListItem]: true,
      [Crepe.Feature.Table]: true,
      [Crepe.Feature.Toolbar]: true,
      [Crepe.Feature.LinkTooltip]: true,
      [Crepe.Feature.Cursor]: true,
      [Crepe.Feature.ImageBlock]: true,
      [Crepe.Feature.BlockEdit]: true,
      [Crepe.Feature.Placeholder]: true,
    },
  })

  crepe.on((listener) => {
    listener.markdownUpdated((_ctx, markdown) => scheduleChange(markdown))
  })

  await crepe.create()
}

// ── Native-facing API ───────────────────────────────────────────────────────

const api = {
  // Replace the whole document. Rebuilds the editor so Milkdown's internal
  // state stays consistent; cheap for note-sized content.
  async setContent(markdown) {
    suppressChange = true
    if (crepe) {
      await crepe.destroy()
      crepe = null
    }
    await buildEditor(markdown ?? '')
    // Release the guard after the load-triggered updates settle.
    setTimeout(() => { suppressChange = false }, 50)
  },

  setReadonly(value) {
    crepe?.setReadonly(Boolean(value))
  },

  setTheme(mode) {
    document.documentElement.dataset.theme = mode === 'dark' ? 'dark' : 'light'
  },

  getMarkdown() {
    return crepe?.getMarkdown() ?? ''
  },
}

window.FacetXEditor = api

// Boot with an empty doc; native will push real content on 'ready'.
buildEditor('').then(() => postToNative({ type: 'ready' }))
