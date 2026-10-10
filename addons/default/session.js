// Session restore: remembers open tabs and reopens them at launch.
let timer = null;
let ready = false;   // never save before restoring, or the empty start tab would overwrite the list

function save({ tabs, storage }) {
  if (!ready || timer) return;
  timer = setTimeout(() => {
    timer = null;
    storage.set("tabs", tabs.list().map((t) => t.url).filter((u) => /^https?:/.test(u)));
  }, 1000);
}

export default {
  name: "Session",
  description: "Reopens your tabs when lean starts.",
  // `ready` fires once per launch, after the first window opens (not on hot reload).
  onReady(_, { storage, tabs }) {
    const saved = storage.get("tabs") || [];
    const open = new Set(tabs.list().map((t) => t.url));
    const blank = tabs.list().length === 1 && !tabs.active().url ? tabs.active() : null;
    // Background tabs insert right after the active one, so open in reverse to keep the order.
    for (const url of [...saved].reverse()) if (!open.has(url)) tabs.open(url, { background: true });
    if (blank && tabs.list().length > 1) { blank.close(); tabs.list()[0].focus(); }
    ready = true;
  },
  setup({ app }) { if (!app.justLaunched) ready = true; },   // hot reload: nothing to restore
  onTabCreated: (_, ctx) => save(ctx),
  onTabLoad: (_, ctx) => save(ctx),
  onTabClosed: (_, ctx) => save(ctx),
};
