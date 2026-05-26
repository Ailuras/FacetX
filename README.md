# DocsBot

A lightweight, dark-themed project dashboard for research and engineering teams. DocsBot serves a single-page web UI from plain JavaScript data files — no build step, no database, just structured project docs.

## Features

- **Four-section dashboard**: Recent Tasks, Research, Engineering, Notes
- **Dark theme**: Gold-accented UI inspired by academic paper aesthetics
- **Zero build**: Data is plain `.js` files; frontend is vanilla JS + CSS
- **Project switcher**: Manage multiple projects from one server
- **Note modal**: Click any note card to read full HTML content inline
- **Cross-references**: Research directions link to engineering tasks via `serves` / `depends_on`

## Quick Start

```bash
# Install
pip install -e .

# Create a project
docsbot init my-project

# Start the server
docsbot serve

# Open http://127.0.0.1:18765
```

## Project Structure

Each project lives in a directory with this layout:

```
projects/my-project/
  data/
    meta.js       -- project identity and navigation
    research.js   -- research directions (R1, R2, ...)
    backlog.js    -- engineering tasks (P0-01, P1-02, ...)
    roadmap.js    -- weekly planning
    changelog.js  -- commit history
    notes.js      -- note index
  notes/
    *.html        -- individual notes
```

All `.js` files in `data/` are plain JavaScript that assign to `window.AUGUR_*` globals. The frontend parses them in a sandbox and renders cards.

## Example Project

An example project is included in `examples/demo/`. If `projects/` is empty, the server automatically falls back to the example.

## Commands

| Command | Description |
|---------|-------------|
| `docsbot serve` | Start the web server (default port 18765) |
| `docsbot serve --stop` | Stop the running server |
| `docsbot serve --daemon` | Run in background |
| `docsbot status` | Show server status and project list |
| `docsbot init NAME` | Create a new project |
| `docsbot lint` | Run syntax check on data files |

## Data Format

See `examples/demo/CLAUDE.md` for the full data format reference.

## License

MIT
