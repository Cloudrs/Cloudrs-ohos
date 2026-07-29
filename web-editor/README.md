# web-editor

CodeMirror 6 bundle for the in-app text editor. **Not part of the HAP build** — the build product is
committed under `entry/src/main/resources/rawfile/editor/`, the same way `entry/libs/` carries
prebuilt Rust artifacts, so day-to-day DevEco builds need no Node toolchain.

## Rebuild

Only needed when `src/main.js` or the dependency versions change.

```bash
cd web-editor && npm install && npm run build
```

Output goes to `../entry/src/main/resources/rawfile/editor/editor.js`. Commit it along with the
source change.

## Notes

- Dependencies are pinned and `package-lock.json` is committed so the bundle is reproducible.
- The language list in `src/main.js` (`LANGUAGES`) must stay in step with
  `CommonUtil.getEditorLanguage` on the ArkTS side. It is also the bundle-size dial — hvigor stores
  `rawfile` assets uncompressed, so every grammar costs its full minified size in app size.
- The bridge contract with ArkTS is documented in `docs/text-edit-plan.md`. The rule that shapes it:
  document content never travels inside a `runJavaScript` script string.
