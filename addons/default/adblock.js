// Ad and tracker blocking: EasyList + EasyPrivacy, compiled by WebKit and applied before requests
// start. The lists ship with the app (scripts/rules.py). Disable this add-on to browse unblocked;
// `rules.togglePause` pauses one site.
export default {
  name: "Ad Blocker",
  description: "Blocks ads and trackers with EasyList and EasyPrivacy.",
  setup({ rules }) {
    rules.bundled();
  },
};
