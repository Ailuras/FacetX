// Build the read-only note preview into a self-contained bundle and vendor it
// into the app's Resources so the Swift/SPM build needs no Node toolchain.
//
//   web/note-editor/src/{index.html,main.js,...}  ->  app/Resources/NotePreview/
//
// Imported CSS is emitted as a sibling bundle.css; KaTeX fonts are inlined as
// data URLs so both files render correctly from file://.

import * as esbuild from 'esbuild'
import { cp, mkdir, rm } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const here = dirname(fileURLToPath(import.meta.url))
const outDir = resolve(here, '../../app/Resources/NotePreview')

await rm(outDir, { recursive: true, force: true })
await mkdir(outDir, { recursive: true })

await esbuild.build({
  entryPoints: [resolve(here, 'src/main.js')],
  bundle: true,
  format: 'iife',
  outfile: resolve(outDir, 'bundle.js'),
  minify: true,
  sourcemap: false,
  loader: {
    '.css': 'css',
    '.woff': 'dataurl',
    '.woff2': 'dataurl',
    '.ttf': 'dataurl',
    '.svg': 'dataurl',
    '.png': 'dataurl',
  },
  // Imported CSS is emitted as a sibling bundle.css (loaded by index.html);
  // url() font/image refs are inlined via the dataurl loaders above so both
  // files are self-contained and load from file:// without relative-path issues.
  logLevel: 'info',
})

await cp(resolve(here, 'src/index.html'), resolve(outDir, 'index.html'))

console.log('Built note preview -> app/Resources/NotePreview/')
