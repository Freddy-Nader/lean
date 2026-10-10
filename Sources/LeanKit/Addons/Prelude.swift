/// JavaScript that runs first in every add-on's JSContext. It turns the flat `native` bridge into
/// the API documented in API.md, and makes every add-on call error-isolated.
enum Prelude {
    static let host = #"""
    (function (native) {
      const listeners = {};
      const fail = (e) => native.fail(String((e && e.stack) ? e + "\n" + e.stack : e));
      const settle = (r) => { if (r && typeof r.then === "function") r.then(undefined, fail); return r; };
      const json = (v) => JSON.stringify(v === undefined ? null : v);

      function tab(t) {
        if (!t) return null;
        return {
          id: t.id, url: t.url, title: t.title,
          eval: (fn, ...args) => new Promise((res, rej) =>
            native.evalInTab(t.id, typeof fn === "function" ? `(${fn})(...${json(args)})` : String(fn),
              (r, err) => err ? rej(new Error(err)) : res(r))),
          send: (event, data) => native.sendToTab(t.id, String(event), json(data)),
          reload: () => native.tabAction(t.id, "reload", ""),
          navigate: (url) => native.tabAction(t.id, "navigate", String(url)),
          close: () => native.tabAction(t.id, "close", ""),
          focus: () => native.tabAction(t.id, "focus", ""),
        };
      }

      const api = {
        tabs: {
          active: () => tab(native.activeTab()),
          list: () => native.listTabs().map(tab),
          open: (url, o) => tab(native.openTab(String(url), !!(o && o.background))),
          close: (id) => native.tabAction(id, "close", ""),
          focus: (id) => native.tabAction(id, "focus", ""),
          onCreated: (fn) => api.hooks.on("tabCreated", fn),
          onLoad: (fn) => api.hooks.on("tabLoaded", fn),
          onClosed: (fn) => api.hooks.on("tabClosed", fn),
        },
        keys: { bind: (k, c) => native.bind(String(k), c == null ? null : String(c)), unbind: (k) => native.bind(String(k), null) },
        ui: {
          toast: (t) => native.toast(String(t)),
          copy: (t) => native.copy(String(t)),
          open: (target, o) => native.openItem(String(target), !!(o && o.reveal)),
        },
        rank: {
          match: (q, text) => native.rankMatch(String(q), String(text)),
          score: (q, text, key) => native.rankScore(String(q), String(text), String(key)),
          pick: (key) => native.rankPick(String(key)),
          forget: (key) => native.rankForget(String(key)),
        },
        downloads: { list: () => native.downloads() },
        app: { get justLaunched() { return native.justLaunched(); } },
        page: { setData: (d) => native.pageData(json(d)) },
        storage: {
          get: (k) => JSON.parse(native.storageAll())[k],
          set: (k, v) => native.storageSet(String(k), json(v)),
          all: () => JSON.parse(native.storageAll()),
        },
        settings: { get: (k) => native.setting(String(k)) },
        rules: {
          bundled: () => native.rulesBundled(),
          add: (id, rules) => native.rulesAdd(String(id), typeof rules === "string" ? rules : JSON.stringify(rules)),
          remove: (id) => native.rulesRemove(String(id)),
        },
        net: {
          fetch: (url, opts) => new Promise((res, rej) => native.fetch(String(url), json(opts || {}), (status, body, err) =>
            err ? rej(new Error(err)) : res({ status, ok: status >= 200 && status < 300,
              text: () => Promise.resolve(body), json: () => Promise.resolve(JSON.parse(body)) }))),
        },
        hooks: { on: (name, fn) => { (listeners[name] = listeners[name] || []).push(fn); } },
        slots: { provide: (name, impl) => native.provide(String(name), impl) },
        palette: { addGroup: (name, provider) => native.paletteGroup(String(name), provider) },
      };

      // JavaScriptCore has no web APIs; minimal URL + URLSearchParams for absolute URLs.
      if (typeof URLSearchParams === "undefined") {
        globalThis.URLSearchParams = class {
          constructor(q = "") {
            this._p = String(q).replace(/^\?/, "").split("&").filter(Boolean).map((kv) => {
              const [k, v = ""] = kv.split("=");
              const d = (x) => { try { return decodeURIComponent(x.replace(/\+/g, " ")); } catch { return x; } };
              return [d(k), d(v)];
            });
          }
          get(k) { const e = this._p.find((p) => p[0] === k); return e ? e[1] : null; }
          has(k) { return this._p.some((p) => p[0] === k); }
          set(k, v) { this.delete(k); this._p.push([k, String(v)]); }
          append(k, v) { this._p.push([k, String(v)]); }
          delete(k) { this._p = this._p.filter((p) => p[0] !== k); }
          keys() { return this._p.map((p) => p[0])[Symbol.iterator](); }
          entries() { return this._p.map((p) => [...p])[Symbol.iterator](); }
          [Symbol.iterator]() { return this.entries(); }
          toString() { return this._p.map(([k, v]) => encodeURIComponent(k) + "=" + encodeURIComponent(v)).join("&"); }
        };
      }
      if (typeof URL === "undefined") {
        globalThis.URL = class {
          constructor(s) {
            const m = String(s).match(/^([a-z][a-z0-9+.-]*:)(?:\/\/(?:[^@\/?#]*@)?([^:\/?#]*)(?::(\d+))?)?([^?#]*)(\?[^#]*)?(#.*)?$/i);
            if (!m) throw new TypeError("Invalid URL: " + s);
            this.protocol = m[1].toLowerCase(); this.hostname = (m[2] || "").toLowerCase(); this.port = m[3] || "";
            this.pathname = m[4] || "/"; this.hash = m[6] || "";
            this.searchParams = new URLSearchParams(m[5] || "");
          }
          get host() { return this.hostname + (this.port ? ":" + this.port : ""); }
          get origin() { return this.protocol + "//" + this.host; }
          get search() { const q = this.searchParams.toString(); return q ? "?" + q : ""; }
          set search(v) { this.searchParams = new URLSearchParams(v); }
          get href() { return this.origin + this.pathname + this.search + this.hash; }
          toString() { return this.href; }
        };
      }

      globalThis.setTimeout = (fn, ms) => native.setTimeout(() => { try { settle(fn()); } catch (e) { fail(e); } }, ms || 0);
      globalThis.console = {
        log: (...a) => native.log(a.map(String).join(" ")),
        error: (...a) => native.log("error: " + a.map(String).join(" ")),
      };

      // Method shorthand `run({on}) {…}` stringifies to something that is not an expression.
      const asExpression = (fn) => {
        const s = String(fn);
        if (/^(async\s+)?(function\b|\(|[A-Za-z_$][\w$]*\s*=>)/.test(s)) return s;
        return s.startsWith("async ") ? "async function " + s.slice(6) : "function " + s;
      };

      globalThis.__lean = {
        api,
        asExpression,
        /// Runs every listener; returns the first synchronous non-undefined result.
        emit(name, payload) {
          let out;
          for (const fn of listeners[name] || []) {
            try { const r = settle(fn(payload)); if (out === undefined && r !== undefined && !(r && r.then)) out = r; }
            catch (e) { fail(e); }
          }
          return out;
        },
        call(fn, ...args) { try { return settle(fn(...args)); } catch (e) { fail(e); } },
      };
    })
    """#

    /// Injected (in the add-on's own content world) before its page code on every page.
    static let page = #"""
    (() => {
      const handlers = {};
      window.__lean_dispatch = (e, d) => (handlers[e] || []).forEach((f) => { try { f(d); } catch (x) { console.error(x); } });
      window.__leanPage = {
        on: (e, f) => { (handlers[e] = handlers[e] || []).push(f); },
        emit: (e, d) => window.webkit.messageHandlers.lean.postMessage({ e: String(e), d: d === undefined ? null : d }),
      };
    })();
    """#
}
