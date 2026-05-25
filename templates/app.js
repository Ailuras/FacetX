// ============================================================
// DocsBot Frontend — Interactive SPA
// ============================================================
// Modules:
//   1. Data Layer      — API wrappers, project loading, serialization
//   2. UI Utilities    — Toast, markdown inline, escape, spinner
//   3. Renderers       — Page render functions (index, research, backlog, notes)
//   4. Drag & Drop     — Full HTML5 DnD with cross-bucket support
//   5. Modal System    — Task/Research editing with draft auto-save
//   6. Keyboard        — ESC, Ctrl+Enter, Ctrl+N shortcuts
//   7. Navigation      — Page switching with fade transitions
//   8. Boot            — Initialization and event wiring
// ============================================================

const API_BASE = '';
let currentProject = null;
let currentPage = 'index';
let projectData = {};

// ============================================================
// 1. Data Layer
// ============================================================

async function api(path) {
  const res = await fetch(API_BASE + path);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

async function apiPost(path, body) {
  const res = await fetch(API_BASE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

async function loadProjects() {
  const data = await api('/api/projects');
  return data.projects || [];
}

async function loadProjectData(projectId) {
  const files = ['meta.js', 'research.js', 'backlog.js', 'roadmap.js', 'changelog.js', 'notes.js'];
  const data = {};
  for (const f of files) {
    try {
      const res = await api(`/api/projects/${encodeURIComponent(projectId)}/data/${f}`);
      data[f] = res.content || '';
    } catch (e) {
      data[f] = '';
    }
  }
  // Parse JS window.AUGUR_* globals
  const sandbox = { window: {} };
  for (const [fname, content] of Object.entries(data)) {
    if (!content) continue;
    try {
      const fn = new Function('window', content);
      fn(sandbox.window);
    } catch (e) {
      console.warn('Parse error in', fname, e);
    }
  }
  return {
    meta: sandbox.window.AUGUR_META || {},
    research: sandbox.window.AUGUR_RESEARCH || [],
    backlog: sandbox.window.AUGUR_BACKLOG || [],
    buckets: sandbox.window.AUGUR_BACKLOG_BUCKETS || [],
    roadmap: sandbox.window.AUGUR_ROADMAP || null,
    changelog: sandbox.window.AUGUR_CHANGELOG || [],
    notes: sandbox.window.AUGUR_NOTES || [],
    raw: data,
  };
}

async function saveDataFile(projectId, filename, content) {
  return apiPost(`/api/projects/${encodeURIComponent(projectId)}/data/${filename}`, { content });
}

// ============================================================
// 2. UI Utilities
// ============================================================

function esc(s) {
  if (s == null) return '';
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function inline(s) {
  if (!s) return '';
  let t = String(s);
  t = t.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  t = t.replace(/(^|[^*])\*([^*\n]+)\*(?=[^*]|$)/g, '$1<em>$2</em>');
  t = t.replace(/`([^`\n]+)`/g, '<code>$1</code>');
  return t;
}

// ---- Toast System ----
function toast(message, type = 'info') {
  const container = document.getElementById('toastContainer');
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.textContent = message;
  container.appendChild(el);

  // Animate in
  requestAnimationFrame(() => {
    el.style.opacity = '0';
    el.style.transform = 'translateY(12px) scale(0.96)';
    el.style.transition = 'opacity 250ms ease, transform 250ms cubic-bezier(0.34, 1.56, 0.64, 1)';
    requestAnimationFrame(() => {
      el.style.opacity = '1';
      el.style.transform = 'translateY(0) scale(1)';
    });
  });

  // Animate out and remove
  setTimeout(() => {
    el.style.transition = 'opacity 200ms ease, transform 200ms ease';
    el.style.opacity = '0';
    el.style.transform = 'translateY(-8px) scale(0.98)';
    setTimeout(() => el.remove(), 220);
  }, 2800);
}

// ---- Loading Spinner ----
function showSpinner(parent) {
  const spinner = document.createElement('div');
  spinner.className = 'docsbot-spinner';
  spinner.innerHTML = `
    <svg width="32" height="32" viewBox="0 0 32 32">
      <circle cx="16" cy="16" r="12" fill="none" stroke="var(--rule-soft)" stroke-width="2"/>
      <circle cx="16" cy="16" r="12" fill="none" stroke="var(--accent)" stroke-width="2"
        stroke-dasharray="56" stroke-dashoffset="56" stroke-linecap="round"
        style="transform-origin:center;animation:spin 1s linear infinite;"/>
    </svg>
    <style>@keyframes spin{to{transform:rotate(360deg)}}</style>
  `;
  spinner.style.cssText = 'display:flex;align-items:center;justify-content:center;padding:80px 20px;flex-direction:column;gap:12px;color:var(--ink-3);font-family:var(--font-mono);font-size:12px;';
  if (parent) parent.appendChild(spinner);
  return spinner;
}

function hideSpinner(spinner) {
  if (spinner) spinner.remove();
}

// ---- Inline Confirm Widget ----
// Replaces a button with a small inline confirm/cancel pair
function showInlineConfirm(button, onConfirm, message) {
  const parent = button.parentNode;

  const wrapper = document.createElement('span');
  wrapper.className = 'inline-confirm';
  wrapper.style.cssText = 'display:inline-flex;align-items:center;gap:6px;font-family:var(--font-mono);font-size:10px;';
  wrapper.innerHTML = `
    <span style="color:var(--p0);">${esc(message)}</span>
    <button class="btn danger sm" style="padding:2px 8px;">确认</button>
    <button class="btn sm" style="padding:2px 8px;">取消</button>
  `;

  const confirmBtn = wrapper.querySelector('.btn.danger');
  const cancelBtn = wrapper.querySelector('.btn:not(.danger)');

  const restoreButton = () => {
    if (wrapper.parentNode) {
      wrapper.replaceWith(button);
    }
  };

  confirmBtn.addEventListener('click', () => {
    onConfirm();
    wrapper.remove();
  });
  cancelBtn.addEventListener('click', restoreButton);

  button.replaceWith(wrapper);

  // Auto-cancel after 5 seconds
  const timeout = setTimeout(() => {
    restoreButton();
  }, 5000);

  // Clean up timeout if wrapper is removed by other means
  const observer = new MutationObserver((mutations) => {
    for (const m of mutations) {
      for (const node of m.removedNodes) {
        if (node === wrapper) {
          clearTimeout(timeout);
          observer.disconnect();
          return;
        }
      }
    }
  });
  if (parent) {
    observer.observe(parent, { childList: true });
  }
}

// ============================================================
// 3. Renderers
// ============================================================

function renderIndex(data) {
  const meta = data.meta;
  const RM = data.roadmap;
  const B = data.backlog;
  const CL = data.changelog;
  const R = data.research;

  // Dashboard stats
  let dashboardHTML = '';
  if (data.buckets.length) {
    const cells = data.buckets.map(b => {
      const n = B.filter(t => t.bucket === b.p).length;
      return `<div class="stat ${b.p.toLowerCase()}"><div class="ribbon"></div><div class="stat-label">${esc(b.p)}</div><div class="stat-num">${n}</div><div class="stat-desc">${esc(b.label)}</div></div>`;
    }).join('');
    dashboardHTML = `<div class="dashboard">${cells}</div>`;
  }

  // Plan weeks
  let planHTML = '';
  if (RM && RM.weeks) {
    const weeks = RM.weeks.map((w, idx) => {
      const cls = idx === 0 ? 'this' : (idx === 1 ? 'next' : 'later');
      const items = (w.items || []).map(it => `<li class="pw-item">${inline(it.text || '')}</li>`).join('');
      return `<div class="pw-card ${cls}"><div class="pw-head"><span class="pw-label">${esc(w.label)}</span><span class="pw-window">${esc(w.window)}</span></div><ul class="pw-items">${items}</ul></div>`;
    }).join('');
    planHTML = `<div class="plan-weeks">${weeks}</div>`;
  }

  // Changelog
  let changelogHTML = '';
  if (CL.length) {
    const rows = CL.slice(0, 10).map(e => {
      const refs = (e.refs || []).map(r => `<span>${esc(r)}</span>`).join('');
      return `<li class="cl-item"><span class="cl-date">${esc(e.date)}</span><span class="cl-sha">${esc(e.short || '')}</span><span class="cl-summary">${inline(e.summary)}</span><span class="cl-refs">${refs}</span></li>`;
    }).join('');
    changelogHTML = `<h3 style="margin-top:24px;">最近变更</h3><ul class="changelog">${rows}</ul>`;
  }

  // Engineering preview
  let engHTML = '';
  if (B.length) {
    const byModule = {};
    for (const t of B) {
      (byModule[t.module] = byModule[t.module] || []).push(t);
    }
    const modules = [
      { id: 'smt', label: 'SMT Core' },
      { id: 'llm', label: 'LLM Loop' },
      { id: 'infra', label: 'Infra' },
    ];
    const cols = modules.map(m => {
      const tasks = (byModule[m.id] || []).slice(0, 5);
      const items = tasks.map(t => {
        const st = t.status && t.status !== 'open' ? ` <span style="font-size:9px;color:var(--ink-3);">[${esc(t.status)}]</span>` : '';
        return `<div style="font-size:12px;padding:3px 0;border-bottom:1px dotted var(--rule-faint);">${esc(t.id)}${st} — ${inline(t.title)}</div>`;
      }).join('');
      return `<div style="flex:1;min-width:200px;"><h4 style="margin:0 0 8px;font-size:13px;">${esc(m.label)}</h4>${items}</div>`;
    }).join('');
    engHTML = `<h3 style="margin-top:24px;">工程队列预览</h3><div style="display:flex;gap:16px;flex-wrap:wrap;">${cols}</div>`;
  }

  return `
    <div class="page-header">
      <h1>${esc(meta.project || 'Project')}</h1>
      <p class="subtitle">${inline(meta.tagline || '')}</p>
    </div>
    ${dashboardHTML}
    ${planHTML}
    ${engHTML}
    ${changelogHTML}
  `;
}

function renderResearch(data) {
  const R = data.research;
  if (!R.length) return '<div class="loading">暂无研究方向</div>';

  const cards = R.map(r => {
    const statusBadge = r.status && r.status !== 'open'
      ? `<span style="font-family:var(--font-mono);font-size:9px;padding:1px 5px;border-radius:2px;background:var(--p${r.status === 'in-progress' ? '1' : r.status === 'done' ? '3' : r.status === 'blocked' ? '0' : '5'}-bg);color:var(--p${r.status === 'in-progress' ? '1' : r.status === 'done' ? '3' : r.status === 'blocked' ? '0' : '5'});">${esc(r.status)}</span>` : '';
    const body = (r.body || []).map(p => `<p style="font-size:13px;line-height:1.55;margin:0 0 8px;">${inline(p)}</p>`).join('');
    return `
      <div class="r-card" data-id="${esc(r.id)}" onclick="editResearch('${esc(r.id)}')">
        <div class="r-card-header">
          <span class="r-id">${esc(r.id)}</span>
          <span class="r-codename">${esc(r.codename || '')}</span>
          ${statusBadge}
        </div>
        <h3>${inline(r.title)} <span class="r-kind">${esc(r.kind)}</span></h3>
        <p class="r-hypothesis">${inline(r.hypothesis || '')}</p>
        ${body}
      </div>`;
  }).join('');

  return `
    <div class="page-header">
      <h1>研究路线</h1>
      <p class="subtitle">研究方向与实现边界</p>
    </div>
    <div class="btn-row">
      <button class="btn primary" onclick="addResearch()">+ 添加研究方向</button>
    </div>
    <div class="r-grid">${cards}</div>
  `;
}

function renderBacklog(data) {
  const B = data.backlog;
  const BB = data.buckets;
  if (!BB.length) return '<div class="loading">暂无工程任务</div>';

  const byBucket = {};
  for (const t of B) {
    (byBucket[t.bucket] = byBucket[t.bucket] || []).push(t);
  }

  const sections = BB.map(b => {
    const tasks = byBucket[b.p] || [];
    const taskHTML = tasks.map((t, idx) => renderTaskCard(t, b.p, idx)).join('');
    return `
      <div class="bucket-section">
        <h2><span class="bucket-badge" style="background:var(--${b.p.toLowerCase()});color:#fff;">${esc(b.p)}</span> ${esc(b.label)}</h2>
        <p class="bucket-lede">${esc(b.desc)}</p>
        <div class="btn-row">
          <button class="btn primary sm" onclick="addTask('${esc(b.p)}')">+ 添加任务</button>
        </div>
        <div class="task-list" data-bucket="${esc(b.p)}">
          ${taskHTML}
        </div>
      </div>`;
  }).join('');

  return `
    <div class="page-header">
      <h1>工程队列</h1>
      <p class="subtitle">从代码缺口反推出来的任务列表</p>
    </div>
    ${sections}
  `;
}

function renderTaskCard(t, bucket, idx) {
  const statusPill = t.status
    ? `<span class="status-pill ${esc(t.status)}">${esc(t.status)}</span>` : '';
  const sizeTag = t.size ? `<span class="tag size-${esc(t.size)}">SIZE · ${esc(t.size)}</span>` : '';
  const serves = (t.serves || []).map(s => {
    if (/^R\d+$/.test(s)) return `<a href="#" onclick="navTo('research');return false;">${esc(s)}</a>`;
    return esc(s);
  }).join(' ');
  const fields = t.fields || {};

  return `
    <div class="task-card ${esc((t.bucket || bucket).toLowerCase())}" draggable="true" data-id="${esc(t.id)}" data-idx="${idx}">
      <div class="task-drag-handle" title="拖拽排序" draggable="false">
        <svg width="12" height="20" viewBox="0 0 12 20" fill="var(--ink-4)">
          <circle cx="3" cy="4" r="1.5"/><circle cx="9" cy="4" r="1.5"/>
          <circle cx="3" cy="10" r="1.5"/><circle cx="9" cy="10" r="1.5"/>
          <circle cx="3" cy="16" r="1.5"/><circle cx="9" cy="16" r="1.5"/>
        </svg>
      </div>
      <div class="task-sidebar">
        <div class="task-id">${esc(t.id)}</div>
        <div class="task-tags">
          <span class="tag">${esc(t.bucket || bucket)}</span>
          ${sizeTag}
        </div>
        ${statusPill}
        <div class="effort">${esc(t.effort || '')}</div>
        <div style="margin-top:auto;display:flex;gap:4px;">
          <button class="btn sm" onclick="event.stopPropagation();editTask('${esc(t.id)}')">编辑</button>
          <button class="btn danger sm" onclick="event.stopPropagation();confirmDeleteTask(this,'${esc(t.id)}')">删除</button>
        </div>
      </div>
      <div class="task-body" onclick="editTask('${esc(t.id)}')">
        <h3>${inline(t.title)}</h3>
        <p class="task-meta"><strong>服务于</strong> ${serves}</p>
        <dl class="task-fields">
          <dt>输入</dt><dd>${inline(fields.input || '')}</dd>
          <dt>产出</dt><dd>${inline(fields.output || '')}</dd>
          <dt>验收</dt><dd>${inline(fields.accept || '')}</dd>
          <dt>备注</dt><dd>${inline(fields.note || '')}</dd>
        </dl>
      </div>
    </div>`;
}

function renderNotes(data) {
  const notes = [...data.notes].sort((a, b) => (b.date || '').localeCompare(a.date || ''));
  const rows = notes.map(n => `
    <a class="note-row" href="${esc(n.path || '#')}" target="_blank">
      <span class="note-date">${esc(n.date || '')}</span>
      <span class="note-title">${esc(n.title)}${n.excerpt ? `<span class="note-excerpt">${esc(n.excerpt)}</span>` : ''}</span>
      <span class="note-tags">${(n.tags || []).map(t => `<span class="note-tag">${esc(t)}</span>`).join('')}</span>
    </a>
  `).join('');

  return `
    <div class="page-header">
      <h1>研究与工程笔记</h1>
      <p class="subtitle">按日期倒序排列</p>
    </div>
    <div class="notes-list">${rows}</div>
  `;
}

// ============================================================
// 4. Drag & Drop System
// ============================================================
// Features:
//   - Drag handle only: only the ⋮⋮ handle initiates drag
//   - Cross-bucket: drag between different bucket sections
//   - Drop indicator: visual placeholder bar shows insert position
//   - Data sync: updates projectData and saves after drop

let dragState = {
  srcEl: null,
  srcId: null,
  srcBucket: null,
  placeholder: null,
};

function createDropPlaceholder() {
  const el = document.createElement('div');
  el.className = 'drop-placeholder';
  el.style.cssText = `
    height: 3px; background: var(--accent); border-radius: 2px;
    margin: 4px 0; opacity: 0; transition: opacity 120ms ease;
    pointer-events: none;
  `;
  return el;
}

function getDragAfterElement(container, y) {
  const cards = [...container.querySelectorAll('.task-card:not(.dragging)')];
  return cards.reduce((closest, child) => {
    const box = child.getBoundingClientRect();
    const offset = y - box.top - box.height / 2;
    if (offset < 0 && offset > closest.offset) {
      return { offset, element: child };
    }
    return closest;
  }, { offset: Number.NEGATIVE_INFINITY }).element;
}

function setupDragAndDrop() {
  const lists = document.querySelectorAll('.task-list');

  lists.forEach(list => {
    list.addEventListener('dragstart', onDragStart);
    list.addEventListener('dragend', onDragEnd);
    list.addEventListener('dragover', onDragOver);
    list.addEventListener('dragleave', onDragLeave);
    list.addEventListener('drop', onDrop);
  });

  // Setup drag handles: only handle initiates drag
  document.querySelectorAll('.task-drag-handle').forEach(handle => {
    const card = handle.closest('.task-card');
    if (!card) return;

    handle.addEventListener('mousedown', () => {
      card.setAttribute('draggable', 'true');
    });
    handle.addEventListener('mouseup', () => {
      // Keep draggable until dragend fires
    });
    handle.addEventListener('mouseleave', () => {
      if (!card.classList.contains('dragging')) {
        card.setAttribute('draggable', 'false');
      }
    });
  });

  // Prevent drag from body click
  document.querySelectorAll('.task-card').forEach(card => {
    card.addEventListener('dragstart', (e) => {
      if (!card.classList.contains('dragging')) {
        e.preventDefault();
      }
    });
  });
}

function onDragStart(e) {
  const card = e.target.closest('.task-card');
  if (!card) return;

  // Only allow drag if started from handle or card already has dragging class
  const handle = card.querySelector('.task-drag-handle');
  if (!handle) return;

  dragState.srcEl = card;
  dragState.srcId = card.dataset.id;
  dragState.srcBucket = card.closest('.task-list')?.dataset.bucket;

  card.classList.add('dragging');
  e.dataTransfer.effectAllowed = 'move';
  e.dataTransfer.setData('text/plain', card.dataset.id);

  // Create placeholder
  dragState.placeholder = createDropPlaceholder();
}

function onDragEnd(e) {
  const card = e.target.closest('.task-card');
  if (card) {
    card.classList.remove('dragging');
    card.setAttribute('draggable', 'false');
  }

  // Remove all placeholders
  document.querySelectorAll('.drop-placeholder').forEach(el => el.remove());
  document.querySelectorAll('.drop-target-above, .drop-target-below').forEach(el => {
    el.classList.remove('drop-target-above', 'drop-target-below');
  });

  dragState = { srcEl: null, srcId: null, srcBucket: null, placeholder: null };
}

function onDragOver(e) {
  e.preventDefault();
  e.dataTransfer.dropEffect = 'move';

  const list = e.currentTarget;
  const afterElement = getDragAfterElement(list, e.clientY);

  // Show placeholder at insert position
  if (dragState.placeholder) {
    if (afterElement) {
      list.insertBefore(dragState.placeholder, afterElement);
    } else {
      list.appendChild(dragState.placeholder);
    }
    dragState.placeholder.style.opacity = '1';
  }
}

function onDragLeave(e) {
  // Only hide if leaving the list entirely, not entering a child
  const list = e.currentTarget;
  const related = e.relatedTarget;
  if (!list.contains(related)) {
    if (dragState.placeholder) {
      dragState.placeholder.style.opacity = '0';
    }
  }
}

function onDrop(e) {
  e.preventDefault();

  const list = e.currentTarget;
  const targetBucket = list.dataset.bucket;
  if (!dragState.srcId || !targetBucket) return;

  // Remove placeholder
  if (dragState.placeholder) {
    dragState.placeholder.remove();
  }

  // Find the card that was dropped on (or near)
  const afterElement = getDragAfterElement(list, e.clientY);

  // Get all cards in target list after drop
  const allCards = [...list.querySelectorAll('.task-card')];
  let insertIndex = allCards.length;
  if (afterElement) {
    insertIndex = allCards.indexOf(afterElement);
  }

  // Update data model
  const srcTask = projectData.backlog.find(t => t.id === dragState.srcId);
  if (!srcTask) return;

  const oldBucket = srcTask.bucket;
  const wasSameBucket = oldBucket === targetBucket;

  // Remove from old position
  const oldIndex = projectData.backlog.findIndex(t => t.id === dragState.srcId);
  projectData.backlog.splice(oldIndex, 1);

  // Update bucket
  srcTask.bucket = targetBucket;

  // Find insert position in global backlog
  // Get tasks in target bucket, find where to insert
  const targetBucketTasks = projectData.backlog.filter(t => t.bucket === targetBucket);

  // Calculate global insert index
  let globalInsertIndex;
  if (insertIndex >= targetBucketTasks.length) {
    // Append after all target bucket tasks
    const lastTargetIdx = projectData.backlog.map(t => t.bucket).lastIndexOf(targetBucket);
    globalInsertIndex = lastTargetIdx + 1;
  } else if (insertIndex <= 0) {
    // Insert before first target bucket task
    const firstTargetIdx = projectData.backlog.findIndex(t => t.bucket === targetBucket);
    globalInsertIndex = firstTargetIdx >= 0 ? firstTargetIdx : projectData.backlog.length;
  } else {
    // Insert at specific position within target bucket
    const targetIndices = [];
    projectData.backlog.forEach((t, i) => { if (t.bucket === targetBucket) targetIndices.push(i); });
    globalInsertIndex = targetIndices[insertIndex] ?? projectData.backlog.length;
  }

  projectData.backlog.splice(globalInsertIndex, 0, srcTask);

  // Save and re-render
  saveBacklogData();
  renderPage();

  const msg = wasSameBucket ? '任务已重新排序' : `任务已移动到 ${targetBucket}`;
  toast(msg, 'success');
}

// ============================================================
// 5. Modal System with Draft Auto-Save
// ============================================================

const DRAFT_PREFIX = 'docsbot_draft_';

function getDraftKey(page, id) {
  return `${DRAFT_PREFIX}${page}_${id}`;
}

function saveDraft(page, id, data) {
  try {
    localStorage.setItem(getDraftKey(page, id), JSON.stringify({
      data,
      savedAt: Date.now(),
    }));
  } catch (e) {
    console.warn('Failed to save draft:', e);
  }
}

function loadDraft(page, id) {
  try {
    const raw = localStorage.getItem(getDraftKey(page, id));
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    // Drafts expire after 7 days
    if (Date.now() - parsed.savedAt > 7 * 24 * 60 * 60 * 1000) {
      localStorage.removeItem(getDraftKey(page, id));
      return null;
    }
    return parsed.data;
  } catch (e) {
    return null;
  }
}

function clearDraft(page, id) {
  localStorage.removeItem(getDraftKey(page, id));
}

function setupModalKeyboard(modalOverlay, onSave) {
  const handler = (e) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      closeModal();
    } else if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      onSave();
    }
  };
  modalOverlay._keyHandler = handler;
  document.addEventListener('keydown', handler);

  // Focus trap
  modalOverlay.addEventListener('click', (e) => {
    if (e.target === modalOverlay) {
      closeModal();
    }
  });
}

function closeModal() {
  const modal = document.querySelector('.modal-overlay');
  if (modal) {
    if (modal._keyHandler) {
      document.removeEventListener('keydown', modal._keyHandler);
    }
    // Fade out
    modal.style.transition = 'opacity 150ms ease';
    modal.style.opacity = '0';
    setTimeout(() => modal.remove(), 160);
  }
}

// ---- Task Modal ----
function editTask(id) {
  const t = projectData.backlog.find(x => x.id === id);
  if (!t) return;
  const f = t.fields || {};

  // Check for draft
  const draft = loadDraft('task', id);
  const values = draft || {
    title: t.title,
    bucket: t.bucket,
    size: t.size,
    effort: t.effort || '',
    status: t.status,
    serves: (t.serves || []).join(', '),
    input: f.input || '',
    output: f.output || '',
    accept: f.accept || '',
    note: f.note || '',
  };

  const modal = document.createElement('div');
  modal.className = 'modal-overlay';
  modal.style.opacity = '0';
  modal.style.transition = 'opacity 150ms ease';
  modal.innerHTML = `
    <div class="modal">
      <div class="modal-header">
        <h2>编辑任务 · ${esc(t.id)}${draft ? ' <span style="font-size:12px;color:var(--accent);font-weight:400;">(已恢复草稿)</span>' : ''}</h2>
        <button class="modal-close" onclick="closeModal()">&times;</button>
      </div>
      <div class="modal-body">
        <div class="edit-grid">
          <label>ID</label><input class="edit-field" id="edit-id" value="${esc(t.id)}" readonly>
          <label>标题</label><input class="edit-field" id="edit-title" value="${esc(values.title)}">
          <label>桶</label>
          <select class="edit-field" id="edit-bucket">
            ${projectData.buckets.map(b => `<option value="${esc(b.p)}" ${b.p === values.bucket ? 'selected' : ''}>${esc(b.p)} · ${esc(b.label)}</option>`).join('')}
          </select>
          <label>大小</label>
          <select class="edit-field" id="edit-size">
            ${['XS','S','M','L','XL'].map(s => `<option value="${s}" ${s === values.size ? 'selected' : ''}>${s}</option>`).join('')}
          </select>
          <label>工作量</label><input class="edit-field" id="edit-effort" value="${esc(values.effort)}">
          <label>状态</label>
          <select class="edit-field" id="edit-status">
            ${['open','in-progress','blocked','done','abandoned'].map(s => `<option value="${s}" ${s === values.status ? 'selected' : ''}>${s}</option>`).join('')}
          </select>
          <label>服务</label><input class="edit-field" id="edit-serves" value="${esc(values.serves)}" placeholder="R1, R2, infra">
          <label>输入</label><textarea class="edit-field" id="edit-input">${esc(values.input)}</textarea>
          <label>产出</label><textarea class="edit-field" id="edit-output">${esc(values.output)}</textarea>
          <label>验收</label><textarea class="edit-field" id="edit-accept">${esc(values.accept)}</textarea>
          <label>备注</label><textarea class="edit-field" id="edit-note">${esc(values.note)}</textarea>
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn" onclick="closeModal()">取消</button>
        <button class="btn primary" onclick="saveTask('${esc(t.id)}')">保存</button>
        <span style="margin-left:auto;font-family:var(--font-mono);font-size:10px;color:var(--ink-4);align-self:center;">Ctrl+Enter 保存 · ESC 关闭</span>
      </div>
    </div>
  `;
  document.body.appendChild(modal);
  requestAnimationFrame(() => { modal.style.opacity = '1'; });

  // Auto-save draft on input
  const fields = ['edit-title', 'edit-bucket', 'edit-size', 'edit-effort', 'edit-status', 'edit-serves', 'edit-input', 'edit-output', 'edit-accept', 'edit-note'];
  fields.forEach(fid => {
    const el = document.getElementById(fid);
    if (el) {
      el.addEventListener('input', () => {
        saveDraft('task', id, {
          title: document.getElementById('edit-title').value,
          bucket: document.getElementById('edit-bucket').value,
          size: document.getElementById('edit-size').value,
          effort: document.getElementById('edit-effort').value,
          status: document.getElementById('edit-status').value,
          serves: document.getElementById('edit-serves').value,
          input: document.getElementById('edit-input').value,
          output: document.getElementById('edit-output').value,
          accept: document.getElementById('edit-accept').value,
          note: document.getElementById('edit-note').value,
        });
      });
    }
  });

  setupModalKeyboard(modal, () => saveTask(t.id));

  // Focus first editable field
  setTimeout(() => document.getElementById('edit-title')?.focus(), 50);
}

function saveTask(oldId) {
  const t = projectData.backlog.find(x => x.id === oldId);
  if (!t) return;

  t.title = document.getElementById('edit-title').value;
  t.bucket = document.getElementById('edit-bucket').value;
  t.size = document.getElementById('edit-size').value;
  t.effort = document.getElementById('edit-effort').value;
  t.status = document.getElementById('edit-status').value;
  t.serves = document.getElementById('edit-serves').value.split(',').map(s => s.trim()).filter(Boolean);
  t.fields = {
    input: document.getElementById('edit-input').value,
    output: document.getElementById('edit-output').value,
    accept: document.getElementById('edit-accept').value,
    note: document.getElementById('edit-note').value,
  };
  t.updated_at = new Date().toISOString().slice(0, 10);

  clearDraft('task', oldId);
  closeModal();
  saveBacklogData();
  renderPage();
  toast('任务已保存', 'success');
}

function confirmDeleteTask(button, id) {
  showInlineConfirm(button, () => {
    deleteTask(id);
  }, '确定删除?');
}

function deleteTask(id) {
  projectData.backlog = projectData.backlog.filter(t => t.id !== id);
  saveBacklogData();
  renderPage();
  toast('任务已删除', 'info');
}

function addTask(bucket) {
  const existing = projectData.backlog.filter(t => t.bucket === bucket);
  const nums = existing.map(t => {
    const m = t.id.match(new RegExp(`^${bucket}-(\\d+)$`));
    return m ? parseInt(m[1]) : 0;
  });
  const nextNum = nums.length ? Math.max(...nums) + 1 : 1;
  const newId = `${bucket}-${String(nextNum).padStart(2, '0')}`;

  const newTask = {
    id: newId,
    bucket: bucket,
    module: 'infra',
    title: '新任务',
    size: 'S',
    effort: '1 d',
    serves: ['longterm'],
    fields: { input: '', output: '', accept: '', note: '' },
    status: 'open',
    date_added: new Date().toISOString().slice(0, 10),
  };
  projectData.backlog.push(newTask);
  saveBacklogData();
  renderPage();
  editTask(newId);
}

// ---- Research Modal ----
function editResearch(id) {
  const r = projectData.research.find(x => x.id === id);
  if (!r) return;

  const draft = loadDraft('research', id);
  const values = draft || {
    codename: r.codename || '',
    title: r.title,
    kind: r.kind,
    module: r.module,
    status: r.status,
    hypothesis: r.hypothesis || '',
    body: (r.body || []).join('\n'),
    deps: (r.depends_on || []).join(', '),
  };

  const modal = document.createElement('div');
  modal.className = 'modal-overlay';
  modal.style.opacity = '0';
  modal.style.transition = 'opacity 150ms ease';
  modal.innerHTML = `
    <div class="modal">
      <div class="modal-header">
        <h2>编辑研究方向 · ${esc(r.id)}${draft ? ' <span style="font-size:12px;color:var(--accent);font-weight:400;">(已恢复草稿)</span>' : ''}</h2>
        <button class="modal-close" onclick="closeModal()">&times;</button>
      </div>
      <div class="modal-body">
        <div class="edit-grid">
          <label>代号</label><input class="edit-field" id="edit-r-codename" value="${esc(values.codename)}">
          <label>标题</label><input class="edit-field" id="edit-r-title" value="${esc(values.title)}">
          <label>类型</label>
          <select class="edit-field" id="edit-r-kind">
            ${['SAFETY','STATIC','NORMALIZATION','MEASUREMENT','A/B','EXPLORATORY'].map(k => `<option value="${k}" ${k === values.kind ? 'selected' : ''}>${k}</option>`).join('')}
          </select>
          <label>模块</label>
          <select class="edit-field" id="edit-r-module">
            ${['smt','llm','infra'].map(m => `<option value="${m}" ${m === values.module ? 'selected' : ''}>${m}</option>`).join('')}
          </select>
          <label>状态</label>
          <select class="edit-field" id="edit-r-status">
            ${['open','in-progress','blocked','done','abandoned'].map(s => `<option value="${s}" ${s === values.status ? 'selected' : ''}>${s}</option>`).join('')}
          </select>
          <label>假设</label><textarea class="edit-field" id="edit-r-hypothesis">${esc(values.hypothesis)}</textarea>
          <label>正文 (每段一行)</label><textarea class="edit-field" id="edit-r-body">${esc(values.body)}</textarea>
          <label>依赖 (逗号分隔)</label><input class="edit-field" id="edit-r-deps" value="${esc(values.deps)}">
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn" onclick="closeModal()">取消</button>
        <button class="btn primary" onclick="saveResearch('${esc(r.id)}')">保存</button>
        <span style="margin-left:auto;font-family:var(--font-mono);font-size:10px;color:var(--ink-4);align-self:center;">Ctrl+Enter 保存 · ESC 关闭</span>
      </div>
    </div>
  `;
  document.body.appendChild(modal);
  requestAnimationFrame(() => { modal.style.opacity = '1'; });

  // Auto-save draft
  const fields = ['edit-r-codename', 'edit-r-title', 'edit-r-kind', 'edit-r-module', 'edit-r-status', 'edit-r-hypothesis', 'edit-r-body', 'edit-r-deps'];
  fields.forEach(fid => {
    const el = document.getElementById(fid);
    if (el) {
      el.addEventListener('input', () => {
        saveDraft('research', id, {
          codename: document.getElementById('edit-r-codename').value,
          title: document.getElementById('edit-r-title').value,
          kind: document.getElementById('edit-r-kind').value,
          module: document.getElementById('edit-r-module').value,
          status: document.getElementById('edit-r-status').value,
          hypothesis: document.getElementById('edit-r-hypothesis').value,
          body: document.getElementById('edit-r-body').value,
          deps: document.getElementById('edit-r-deps').value,
        });
      });
    }
  });

  setupModalKeyboard(modal, () => saveResearch(r.id));
  setTimeout(() => document.getElementById('edit-r-title')?.focus(), 50);
}

function saveResearch(id) {
  const r = projectData.research.find(x => x.id === id);
  if (!r) return;

  r.codename = document.getElementById('edit-r-codename').value;
  r.title = document.getElementById('edit-r-title').value;
  r.kind = document.getElementById('edit-r-kind').value;
  r.module = document.getElementById('edit-r-module').value;
  r.status = document.getElementById('edit-r-status').value;
  r.hypothesis = document.getElementById('edit-r-hypothesis').value;
  r.body = document.getElementById('edit-r-body').value.split('\n').filter(Boolean);
  r.depends_on = document.getElementById('edit-r-deps').value.split(',').map(s => s.trim()).filter(Boolean);
  r.updated_at = new Date().toISOString().slice(0, 10);

  clearDraft('research', id);
  closeModal();
  saveResearchData();
  renderPage();
  toast('研究方向已保存', 'success');
}

function addResearch() {
  const nums = projectData.research.map(r => {
    const m = r.id.match(/^R(\d+)$/);
    return m ? parseInt(m[1]) : 0;
  });
  const nextNum = nums.length ? Math.max(...nums) + 1 : 1;
  const newR = {
    id: `R${nextNum}`,
    codename: '',
    title: '新研究方向',
    kind: 'EXPLORATORY',
    module: 'infra',
    hypothesis: '',
    body: [],
    depends_on: [],
    status: 'open',
    date_added: new Date().toISOString().slice(0, 10),
  };
  projectData.research.push(newR);
  saveResearchData();
  renderPage();
  editResearch(newR.id);
}

// ============================================================
// 6. Data Serialization
// ============================================================

function serializeBacklog() {
  const BB = projectData.buckets;
  const B = projectData.backlog;
  const lines = [
    '// docs/data/backlog.js',
    '// 工程任务 backlog。新增 task = 在 AUGUR_BACKLOG 数组追加一条对象。',
    '// schema(task):',
    '//   id          — 永久 anchor 契约(如 "P0-01")',
    '//   bucket      — 必须命中 AUGUR_BACKLOG_BUCKETS 中的某个 p',
    '//   module      — smt / llm / infra',
    '//   title       — 卡片 h3',
    '//   size        — XS / S / M / L / XL',
    '//   effort      — 字符串(如 "2-3 d","1-2 wk")',
    '//   serves      — R-id 字符串数组,或 ["R-all"] / ["infra"] / ["longterm"]',
    '//   fields      — { input, output, accept, note }',
    '//   status      — open / in-progress / blocked / done / abandoned',
    '//   date_added  — YYYY-MM-DD',
    '//   updated_at  — YYYY-MM-DD,可选',
    '',
    'window.AUGUR_BACKLOG_BUCKETS = ' + JSON.stringify(BB, null, 2) + ';',
    '',
    'window.AUGUR_BACKLOG = [',
  ];
  for (const t of B) {
    lines.push('  {')
    lines.push(`    id: "${t.id}",`);
    lines.push(`    bucket: "${t.bucket}",`);
    lines.push(`    module: "${t.module}",`);
    lines.push(`    title: "${t.title}",`);
    if (t.size) lines.push(`    size: "${t.size}",`);
    if (t.effort) lines.push(`    effort: "${t.effort}",`);
    lines.push(`    serves: ${JSON.stringify(t.serves)},`);
    lines.push(`    fields: {`);
    lines.push(`      input:  ${JSON.stringify(t.fields?.input || '')},`);
    lines.push(`      output: ${JSON.stringify(t.fields?.output || '')},`);
    lines.push(`      accept: ${JSON.stringify(t.fields?.accept || '')},`);
    lines.push(`      note:   ${JSON.stringify(t.fields?.note || '')},`);
    lines.push('    },');
    lines.push(`    status: "${t.status}",`);
    lines.push(`    date_added: "${t.date_added}",`);
    if (t.updated_at) lines.push(`    updated_at: "${t.updated_at}",`);
    lines.push('  },');
  }
  lines.push('];');
  return lines.join('\n');
}

function serializeResearch() {
  const R = projectData.research;
  const lines = [
    '// docs/data/research.js',
    '// 研究方向 R1-Rn 数据。',
    '',
    'window.AUGUR_RESEARCH = [',
  ];
  for (const r of R) {
    lines.push('  {');
    lines.push(`    id: "${r.id}",`);
    if (r.codename) lines.push(`    codename: "${r.codename}",`);
    lines.push(`    title: "${r.title}",`);
    lines.push(`    kind: "${r.kind}",`);
    lines.push(`    module: "${r.module}",`);
    lines.push(`    hypothesis: ${JSON.stringify(r.hypothesis || '')},`);
    lines.push('    body: [');
    for (const p of (r.body || [])) {
      lines.push(`      ${JSON.stringify(p)},`);
    }
    lines.push('    ],');
    lines.push(`    depends_on: ${JSON.stringify(r.depends_on || [])},`);
    lines.push(`    status: "${r.status}",`);
    lines.push(`    date_added: "${r.date_added}",`);
    if (r.updated_at) lines.push(`    updated_at: "${r.updated_at}",`);
    lines.push('  },');
  }
  lines.push('];');
  return lines.join('\n');
}

async function saveBacklogData() {
  try {
    await saveDataFile(currentProject, 'backlog.js', serializeBacklog());
    toast('已保存到 backlog.js', 'success');
  } catch (e) {
    toast('保存失败: ' + e.message, 'error');
  }
}

async function saveResearchData() {
  try {
    await saveDataFile(currentProject, 'research.js', serializeResearch());
    toast('已保存到 research.js', 'success');
  } catch (e) {
    toast('保存失败: ' + e.message, 'error');
  }
}

// ============================================================
// 7. Navigation with Page Transitions
// ============================================================

function navTo(page) {
  currentPage = page;
  document.querySelectorAll('.nav-tab').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.page === page);
  });
  renderPage();
}

function renderPage() {
  const main = document.getElementById('main');

  // Fade out current content
  if (main.firstChild) {
    main.style.transition = 'opacity 120ms ease';
    main.style.opacity = '0';
  }

  setTimeout(() => {
    switch (currentPage) {
      case 'index': main.innerHTML = renderIndex(projectData); break;
      case 'research': main.innerHTML = renderResearch(projectData); break;
      case 'backlog':
        main.innerHTML = renderBacklog(projectData);
        setupDragAndDrop();
        break;
      case 'notes': main.innerHTML = renderNotes(projectData); break;
    }

    // Fade in new content
    main.style.opacity = '0';
    requestAnimationFrame(() => {
      main.style.transition = 'opacity 200ms ease';
      main.style.opacity = '1';
    });
  }, main.style.opacity === '0' ? 0 : 120);
}

// ============================================================
// 8. Keyboard Shortcuts
// ============================================================

function setupKeyboardShortcuts() {
  document.addEventListener('keydown', (e) => {
    // ESC closes modal (handled in modal setup, but also global fallback)
    if (e.key === 'Escape') {
      const modal = document.querySelector('.modal-overlay');
      if (modal && document.activeElement?.tagName !== 'SELECT') {
        closeModal();
      }
    }

    // Ctrl+N: Add new task in backlog page
    if (e.key === 'n' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      if (currentPage === 'backlog' && projectData.buckets?.length) {
        const firstBucket = projectData.buckets[0].p;
        addTask(firstBucket);
      }
    }
  });
}

// ============================================================
// 9. Boot
// ============================================================

async function boot() {
  const main = document.getElementById('main');
  const spinner = showSpinner(main);

  // Load projects
  const projects = await loadProjects();
  const select = document.getElementById('projectSelect');
  select.innerHTML = projects.map(p => `<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('');

  if (projects.length) {
    currentProject = projects[0].id;
    projectData = await loadProjectData(currentProject);
    hideSpinner(spinner);
    renderPage();
  } else {
    hideSpinner(spinner);
    main.innerHTML = '<div class="loading">暂无项目。使用 <code>docsbot init &lt;name&gt;</code> 创建一个。</div>';
  }

  // Event handlers
  select.addEventListener('change', async () => {
    currentProject = select.value;
    main.style.opacity = '0';
    const s = showSpinner(main);
    projectData = await loadProjectData(currentProject);
    hideSpinner(s);
    renderPage();
  });

  document.querySelectorAll('.nav-tab').forEach(btn => {
    btn.addEventListener('click', () => navTo(btn.dataset.page));
  });

  setupKeyboardShortcuts();
}

boot().catch(e => {
  document.getElementById('main').innerHTML = `<div class="loading" style="color:var(--p0);">加载失败: ${esc(e.message)}</div>`;
});
