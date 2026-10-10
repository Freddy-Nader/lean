// Dark mode on any site, like Comet's ⌥N. Remembered per site, plus "dark everywhere".
// Sites that are already dark are left alone; images and video are kept as they are.
const host = (url) => { try { return new URL(url).hostname.replace(/^www\./, ""); } catch { return ""; } };

function publish({ storage, page }) {
  page.setData({ all: !!storage.get("all"), sites: storage.get("sites") || [] });
}

export default {
  name: "Dark Mode",
  description: "⌥N turns any site dark. Remembered per site.",
  setup: publish,

  commands: {
    "darkmode.toggle": {
      title: "Toggle Dark Mode for This Site",
      key: "alt+n",
      run(ctx) {
        const t = ctx.tabs.active();
        const h = t && host(t.url);
        if (!h) return;
        const sites = new Set(ctx.storage.get("sites") || []);
        const all = !!ctx.storage.get("all");
        // With "dark everywhere" on, the site list holds exceptions instead.
        sites.has(h) ? sites.delete(h) : sites.add(h);
        ctx.storage.set("sites", [...sites]);
        publish(ctx);
        t.send("set", all !== sites.has(h));
      },
    },
    "darkmode.everywhere": {
      title: "Dark Mode Everywhere",
      run(ctx) {
        ctx.storage.set("all", !ctx.storage.get("all"));
        ctx.storage.set("sites", []);
        publish(ctx);
        for (const t of ctx.tabs.list()) t.send("set", !!ctx.storage.get("all"));
        ctx.ui.toast(ctx.storage.get("all") ? "Dark mode everywhere" : "Dark mode per site");
      },
    },
  },

  page: {
    match: ["*://*/*"],
    runAt: "start",
    run({ on, data }) {
      const h = location.hostname.replace(/^www\./, "");
      const want = data && (data.all !== (data.sites || []).includes(h));
      const style = document.createElement("style");
      style.textContent = `
        html { filter: invert(1) hue-rotate(180deg) !important; background: #fff !important; }
        img, video, picture, canvas, svg image, iframe, embed, object,
        [style*="background-image"] { filter: invert(1) hue-rotate(180deg) !important; }`;
      const on_ = () => (document.head || document.documentElement).appendChild(style);
      const off = () => style.remove();
      const luminance = (el) => {
        const m = getComputedStyle(el).backgroundColor.match(/\d+(\.\d+)?/g);
        if (!m || (m[3] !== undefined && +m[3] === 0)) return null;
        const [r, g, b] = m.map(Number);
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
      };
      // Already-dark sites stay as they are.
      const nativelyDark = () => {
        off();
        const l = luminance(document.body) ?? luminance(document.documentElement) ?? 1;
        return l < 0.4;
      };
      if (want) {
        on_();
        document.addEventListener("DOMContentLoaded", () => { if (!nativelyDark()) on_(); }, { once: true });
      }
      on("set", (v) => { if (v && !nativelyDark()) on_(); else off(); });
    },
  },
};
