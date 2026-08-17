/* AppCleaner frontend – talks to pywebview.api */

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

const state = {
  apps: [],
  selectedApp: null,
  scanResults: [],
  scanning: false,
};

// ---------- UI helpers ----------
function setStatus(text) {
  $("#statusText").textContent = text || "Ready.";
}

function setProgress(pct, indeterminate = false) {
  const bar = $("#progressBar");
  if (indeterminate) {
    bar.classList.add("indeterminate");
    bar.style.width = "30%";
  } else {
    bar.classList.remove("indeterminate");
    bar.style.width = `${Math.max(0, Math.min(100, pct))}%`;
  }
}

function showView(name) {
  $("#dropView").classList.toggle("hidden", name !== "drop");
  $("#listView").classList.toggle("hidden", name !== "list");
}

function showModal(title, body, buttons) {
  $("#modalTitle").textContent = title;
  $("#modalBody").textContent = body;
  const actions = $("#modalActions");
  actions.innerHTML = "";
  buttons.forEach((b) => {
    const btn = document.createElement("button");
    btn.className = `btn btn-small ${b.danger ? "btn-danger" : ""}`;
    btn.textContent = b.label;
    btn.onclick = () => {
      $("#modalOverlay").classList.add("hidden");
      if (b.onClick) b.onClick();
    };
    actions.appendChild(btn);
  });
  $("#modalOverlay").classList.remove("hidden");
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function iconHtml(app) {
  if (app.icon) {
    return `<img src="${app.icon}" alt="" draggable="false">`;
  }
  return "📦";
}

function formatAppRow(app) {
  const row = document.createElement("div");
  row.className = "app-row";
  row.dataset.path = app.path;
  row.setAttribute("role", "button");
  row.tabIndex = 0;
  row.innerHTML = `
    <div class="app-icon">${iconHtml(app)}</div>
    <div class="app-row-text">
      <div class="app-row-name">${escapeHtml(app.name)}</div>
      <div class="app-row-path">${escapeHtml(app.path)}</div>
    </div>
    <div class="app-row-version">${escapeHtml(app.version || "")}</div>
  `;
  const activate = (e) => {
    e.preventDefault();
    e.stopPropagation();
    selectApp(app);
  };
  row.addEventListener("click", activate);
  row.addEventListener("keydown", (e) => {
    if (e.key === "Enter" || e.key === " ") activate(e);
  });
  return row;
}

function selectApp(app) {
  state.selectedApp = app;
  $$(".app-row").forEach((r) =>
    r.classList.toggle("selected", r.dataset.path === app.path)
  );
  $("#detailName").textContent = app.name;
  $("#detailSub").textContent = `${app.path}${app.version ? " · v" + app.version : ""}`;
  $("#detailWarning").textContent = app.protected
    ? "This appears to be a system or Apple application. Removal is blocked for safety."
    : "";
  $("#resultsList").innerHTML =
    '<div class="empty-results">Click Scan to look for leftover files.</div>';
  $("#resultsSummary").textContent = "";
  $("#scanBtn").disabled = false;
  $("#removeBtn").disabled = true;
  $("#selectAllBtn").disabled = true;
  $("#deselectAllBtn").disabled = true;
  setStatus(`Selected ${app.name}`);
}

function renderResults(data) {
  state.scanResults = data.items || [];
  const list = $("#resultsList");
  list.innerHTML = "";

  if (!state.scanResults.length) {
    list.innerHTML =
      '<div class="empty-results">No related files found.<br>The application may already be clean.</div>';
    $("#resultsSummary").textContent = "0 items";
    $("#removeBtn").disabled = true;
    return;
  }

  state.scanResults.forEach((item, idx) => {
    const row = document.createElement("div");
    row.className = `result-row${item.protected ? " protected" : ""}`;
    const confClass = `confidence-${item.confidence}`;
    const checked = item.selected && !item.protected;
    row.innerHTML = `
      <div class="result-checkbox ${checked ? "checked" : ""} ${item.protected ? "locked" : ""}"
           data-idx="${idx}">${item.protected ? "🔒" : checked ? "☑" : "☐"}</div>
      <div class="result-text">
        <div class="result-path">${escapeHtml(item.path)}</div>
        <div class="result-meta">
          <span class="confidence-badge ${confClass}">${item.confidence.toUpperCase()}</span>
          <span class="result-size">${item.size_human}</span>
          <span class="result-reason">${escapeHtml(item.reason)}</span>
        </div>
      </div>
    `;
    if (!item.protected) {
      row.addEventListener("click", () => toggleItem(idx));
    }
    list.appendChild(row);
  });

  updateSelectionUI();
}

function toggleItem(idx) {
  const item = state.scanResults[idx];
  if (!item || item.protected) return;
  item.selected = !item.selected;
  renderResults({ items: state.scanResults });
}

function updateSelectionUI() {
  const selected = state.scanResults.filter((i) => i.selected && !i.protected);
  const totalSize = selected.reduce((s, i) => s + i.size, 0);
  $("#resultsSummary").textContent = `${selected.length} of ${state.scanResults.length} selected · ${humanSize(totalSize)}`;
  $("#removeBtn").disabled = selected.length === 0;
  $("#selectAllBtn").disabled = false;
  $("#deselectAllBtn").disabled = false;
}

function humanSize(n) {
  const units = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  return i === 0 ? `${n} B` : `${n.toFixed(1)} ${units[i]}`;
}

// ---------- Drag & drop (called from Python via evaluate_js) ----------
window.__appCleanerHandleDrop = async function (paths) {
  if (!paths || !paths.length) return;
  const path = paths[0];
  setStatus(`Dropped: ${path}`);
  $("#dropZone").classList.remove("drag-over");

  try {
    const app = await pywebview.api.inspect_app(path);
    if (!app) {
      setStatus("That doesn’t look like a macOS application (.app).");
      showModal(
        "Not an application",
        "Drop a .app bundle (from /Applications or elsewhere).",
        [{ label: "OK" }]
      );
      return;
    }
    await ensureAppInList(app);
    showView("list");
    selectApp(app);
  } catch (e) {
    setStatus("Drop failed: " + e);
  }
};

async function ensureAppInList(app) {
  if (!state.apps.length) await loadApps();
  const existing = state.apps.find((a) => a.path === app.path);
  if (existing) {
    if (app.icon && !existing.icon) {
      existing.icon = app.icon;
      const rows = $$(".app-row");
      for (const row of rows) {
        if (row.dataset.path === app.path) {
          const iconEl = row.querySelector(".app-icon");
          if (iconEl) iconEl.innerHTML = iconHtml(existing);
          break;
        }
      }
    }
    return existing;
  }
  state.apps.unshift(app);
  const list = $("#appList");
  const empty = list.querySelector(".empty-hint");
  if (empty) empty.remove();
  list.prepend(formatAppRow(app));
  $("#sidebarStatus").textContent = `${state.apps.length} apps`;
  return app;
}

// ---------- API calls ----------
async function loadApps() {
  setStatus("Loading installed applications…");
  setProgress(0, true);
  try {
    const apps = await pywebview.api.list_installed_apps();
    state.apps = apps;
    const list = $("#appList");
    list.innerHTML = "";
    if (!apps.length) {
      list.innerHTML = '<div class="empty-hint">No applications found.</div>';
    } else {
      apps.forEach((a) => list.appendChild(formatAppRow(a)));
    }
    $("#sidebarStatus").textContent = `${apps.length} apps`;
    setStatus(`Loaded ${apps.length} applications.`);
  } catch (e) {
    setStatus("Failed to list applications: " + e);
  } finally {
    setProgress(0);
  }
}

async function doScan() {
  if (!state.selectedApp || state.scanning) return;
  state.scanning = true;
  $("#scanBtn").disabled = true;
  $("#cancelBtn").disabled = false;
  $("#removeBtn").disabled = true;
  setProgress(0, true);
  setStatus(`Scanning for leftovers of ${state.selectedApp.name}…`);

  try {
    const data = await pywebview.api.scan_app(
      state.selectedApp.path,
      state.selectedApp.bundle_id || "",
      state.selectedApp.name
    );
    if (data.cancelled) {
      setStatus("Scan cancelled.");
    } else {
      renderResults(data);
      setStatus(
        `Found ${data.count} item(s) · ${data.total_size_human} potential reclaim.`
      );
    }
  } catch (e) {
    setStatus("Scan failed: " + e);
  } finally {
    state.scanning = false;
    $("#scanBtn").disabled = false;
    $("#cancelBtn").disabled = true;
    setProgress(0);
  }
}

async function doRemove() {
  const selected = state.scanResults.filter((i) => i.selected && !i.protected);
  if (!selected.length) return;

  showModal(
    "Move to Trash?",
    `You are about to move ${selected.length} item(s) to the Trash.\n\nThis cannot be undone from inside AppCleaner (you can still recover from Trash).`,
    [
      { label: "Cancel" },
      {
        label: "Move to Trash",
        danger: true,
        onClick: async () => {
          setStatus("Moving items to Trash…");
          setProgress(0, true);
          try {
            const res = await pywebview.api.remove_items(
              selected.map((i) => i.path)
            );
            setStatus(
              `Moved ${res.removed_count} item(s) to Trash.${
                res.errors.length ? ` ${res.errors.length} error(s).` : ""
              }`
            );
            await doScan();
          } catch (e) {
            setStatus("Remove failed: " + e);
          } finally {
            setProgress(0);
          }
        },
      },
    ]
  );
}

async function checkPermissions() {
  try {
    const info = await pywebview.api.check_full_disk_access();
    if (!info.has_full_disk_access) {
      showModal(
        "Full Disk Access Required",
        info.message +
          "\n\nWithout Full Disk Access the scanner cannot see Containers, some Library folders, and other protected locations.",
        [
          { label: "Later" },
          {
            label: "Open Settings",
            onClick: () => pywebview.api.open_full_disk_access_settings(),
          },
        ]
      );
    }
  } catch (_) {
    /* ignore */
  }
}

// ---------- Event wiring ----------
async function openChooseDialog() {
  setStatus("Opening application picker…");
  try {
    if (!window.pywebview || !window.pywebview.api) {
      setStatus("App is still loading — try again in a moment.");
      return;
    }
    const app = await pywebview.api.choose_application();
    if (!app) {
      setStatus("No application selected.");
      return;
    }
    showView("list");
    await ensureAppInList(app);
    selectApp(app);
    setStatus(`Selected ${app.name}`);
  } catch (e) {
    setStatus("Could not open picker: " + e);
    showModal(
      "Could not open picker",
      String(e) +
        "\n\nTip: use the list button (☰) and click an app, or drag a .app onto the window.",
      [{ label: "OK" }]
    );
  }
}

function wireEvents() {
  $("#listToggleBtn").addEventListener("click", () => {
    showView("list");
    if (!state.apps.length) loadApps();
  });

  $("#chooseBtn").addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    openChooseDialog();
  });

  $("#dropChooseBtn").addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    openChooseDialog();
  });

  // Whole drop zone click (except the button, which has its own handler) opens picker
  $("#dropZone").addEventListener("click", (e) => {
    if (e.target.closest("button")) return;
    openChooseDialog();
  });

  $("#scanBtn").addEventListener("click", doScan);
  $("#cancelBtn").addEventListener("click", () => {
    pywebview.api.cancel_scan();
    setStatus("Cancelling…");
  });
  $("#removeBtn").addEventListener("click", doRemove);

  $("#selectAllBtn").addEventListener("click", () => {
    state.scanResults.forEach((i) => {
      if (!i.protected) i.selected = true;
    });
    renderResults({ items: state.scanResults });
  });
  $("#deselectAllBtn").addEventListener("click", () => {
    state.scanResults.forEach((i) => (i.selected = false));
    renderResults({ items: state.scanResults });
  });

  $("#searchInput").addEventListener("input", (e) => {
    const q = e.target.value.toLowerCase().trim();
    $$(".app-row").forEach((row) => {
      const name = row.querySelector(".app-row-name").textContent.toLowerCase();
      row.style.display = !q || name.includes(q) ? "" : "none";
    });
  });

  // Visual feedback for drag (Python also handles preventDefault)
  const zone = $("#dropZone");
  ["dragenter", "dragover"].forEach((evt) => {
    zone.addEventListener(evt, (e) => {
      e.preventDefault();
      zone.classList.add("drag-over");
    });
  });
  zone.addEventListener("dragleave", () => {
    zone.classList.remove("drag-over");
  });
  // JS-side drop is a backup; primary path is Python DOMEventHandler → __appCleanerHandleDrop
  zone.addEventListener("drop", (e) => {
    e.preventDefault();
    zone.classList.remove("drag-over");
  });
}

// ---------- Boot ----------
window.addEventListener("pywebviewready", async () => {
  wireEvents();
  await checkPermissions();
  setStatus("Ready. Drop an app or browse installed applications.");
});
