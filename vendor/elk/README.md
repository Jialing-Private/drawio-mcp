# ELK Layout Vendor

Two artifacts are vendored here:

- `drawio-elk.min.js` — ESM bundle from drawio-elk's `dist/elk.min.js`.
  Exports `default` (ELK engine class) plus `ElkLayout`, `ElkAdapter`,
  `ElkApplier` (the mxGraph ↔ ELK bridge). build-html.js wraps it in
  an IIFE and aliases all four to `globalThis.{ELK,ElkLayout,
  ElkAdapter,ElkApplier}` so the inlined viewer scripts see them as
  bare globals (`new ELK()`, `new ElkLayout(...)`, etc.).
- `mxElkLayout.js` — thin compatibility shim that preserves the
  historical `buildElkGraph` / `applyElkLayout` API used by
  shared.js's postLayout flow. Internally delegates to `ElkAdapter` +
  `ElkApplier` from the bundle. The original (~400-line) flat-mode
  adapter has been retired — the bundle's bridge does hierarchical
  (compound) conversion, matching drawio-dev.

Vendored to keep this repo self-contained — see issue #29.

## Versioning

`drawio-elk.min.js`'s first line is a banner of the form:

```
/*! @drawio/elk <semver>+commit.<sha> (built <yyyy-mm-dd>) */
```

To inspect the version of the vendored copy:

```sh
head -1 drawio-elk.min.js
```

`mxElkLayout.js` has no banner — it's a thin mxGraph adapter.

## Refreshing

Build the ESM bundle in the drawio-elk repo and copy:

```sh
cd ../../drawio-elk
npm run build
cp dist/elk.min.js ../drawio-mcp/mcp-app-server/vendor/elk/drawio-elk.min.js
```

The `mxElkLayout.js` shim only needs updating if the bridge's API
changes (it currently uses `ElkAdapter.convert` /
`ElkAdapter.getElkToCellMap` / `ElkApplier.apply`).
