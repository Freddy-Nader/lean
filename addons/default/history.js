// History: remembers visited pages and offers them in the palette, ranked by match and frecency.
// Dedupes by meaning (no tracking params, no www, no trailing slash) and sinks abandoned searches:
// a search replaced by another one within a minute was probably a typo or a dead end.
const MAX = 5000;
const TRACKING = /^(utm_\w+|fbclid|gclid|dclid|msclkid|mc_eid|igshid|ref_src)$/i;
const SEARCH = /[?&](q|query|p|search_query)=/;

let entries = null;   // key → { url, title, visits, last, abandoned }
let saveTimer = null;
let lastSearch = null;

function norm(raw) {
  try {
    const u = new URL(raw);
    if (!/^https?:$/.test(u.protocol)) return null;
    for (const k of [...u.searchParams.keys()]) if (TRACKING.test(k)) u.searchParams.delete(k);
    u.hash = "";
    const host = u.hostname.replace(/^www\./, "");
    const path = u.pathname.replace(/\/$/, "");
    return host + path + (u.search || "");
  } catch { return null; }
}

function save(storage) {
  if (saveTimer) return;
  saveTimer = setTimeout(() => {
    saveTimer = null;
    // Bookmarks are never evicted; the rest keeps the most recent MAX.
    const all = Object.entries(entries).sort((a, b) => (b[1].bookmark - a[1].bookmark) || (b[1].last - a[1].last)).slice(0, MAX);
    entries = Object.fromEntries(all);
    storage.set("entries", entries);
  }, 3000);
}

export default {
  name: "History",
  description: "Remembers visited pages and suggests them in the palette.",

  setup({ storage, palette, rank, tabs }) {
    entries = storage.get("entries") || {};
    palette.addGroup("History", (q) => {
      if (!q) return [];
      const open = new Set(tabs.list().map((t) => norm(t.url)));   // open tabs already show as "switch to tab"
      return Object.entries(entries)
        .filter(([key]) => !open.has(key))
        .map(([key, e]) => {
          const s = rank.score(q, (e.title || "") + " " + key, "hist:" + key);
          return s == null ? null : { e, key, s: s * (e.abandoned ? 0.3 : 1) * (e.bookmark ? 1.5 : 1) * (1 + Math.log1p(e.visits) / 4) };
        })
        .filter(Boolean)
        .sort((a, b) => b.s - a.s)
        .slice(0, 6)
        .map(({ e, key }) => ({
          title: e.title || key,
          subtitle: key,
          run: () => { rank.pick("hist:" + key); tabs.active() ? tabs.active().navigate(e.url) : tabs.open(e.url); },
        }));
    });
  },

  commands: {
    "history.clear": {
      title: "Clear History",
      run({ storage, ui }) { entries = {}; storage.set("entries", {}); ui.toast("History cleared"); },
    },
  },

  // From the import add-on: { kind: "history" | "bookmarks", items: [{ url, title, visits?, last? }] }.
  onImport({ kind, items }, { storage }) {
    for (const it of items) {
      const key = norm(it.url);
      if (!key) continue;
      const e = entries[key] || { url: it.url, visits: 0, last: 0 };
      e.title = e.title || it.title;
      e.visits += it.visits || 0;
      e.last = Math.max(e.last, it.last || 0);
      if (kind === "bookmarks") e.bookmark = true;
      entries[key] = e;
    }
    save(storage);
  },

  onTabLoad(tab, { storage }) {
    const key = norm(tab.url);
    if (!key) return;
    const now = Date.now();
    const e = entries[key] || { url: tab.url, visits: 0 };
    e.title = tab.title;
    e.visits += 1;
    e.last = now;
    e.url = tab.url;
    entries[key] = e;
    if (SEARCH.test(tab.url)) {
      if (lastSearch && lastSearch.key !== key && now - lastSearch.at < 60000 && entries[lastSearch.key]) {
        entries[lastSearch.key].abandoned = true;
      }
      lastSearch = { key, at: now };
    }
    save(storage);
  },
};
