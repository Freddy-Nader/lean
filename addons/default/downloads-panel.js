// Recent downloads in the palette: ↵ opens the file, and "Show Downloads" reveals the latest one.
const name = (p) => p.split("/").pop();

export default {
  name: "Downloads Panel",
  description: "Lists recent downloads in the palette.",
  setup({ palette, downloads, ui }) {
    palette.addGroup("Downloads", (q) =>
      downloads.list()
        .filter((d) => d.path && (!q || name(d.path).toLowerCase().includes(q.toLowerCase()) || "downloads".startsWith(q.toLowerCase())))
        .slice(0, 5)
        .map((d) => ({
          title: name(d.path),
          subtitle: d.failed ? "failed" : d.done ? d.path : "downloading…",
          run: () => ui.open(d.path),
        })));
  },
  commands: {
    "downloads.reveal": {
      title: "Show Latest Download",
      key: "cmd+alt+l",
      run({ downloads, ui }) {
        const d = downloads.list().find((d) => d.path);
        if (d) ui.open(d.path, { reveal: true }); else ui.toast("No downloads yet");
      },
    },
  },
};
