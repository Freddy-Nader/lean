export default {
  name: "Copy Link",
  description: "⌘⇧C copies the current page's address.",
  commands: {
    "link.copy": {
      title: "Copy Link",
      key: "cmd+shift+c",
      run({ tabs, ui }) {
        const t = tabs.active();
        if (!t || !t.url) return;
        ui.copy(t.url);
        ui.toast("Copied " + t.url);
      },
    },
  },
};
