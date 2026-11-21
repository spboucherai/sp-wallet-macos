<!-- spb-source-governance:start -->
## Source header policy (SP Boucher)

When creating or modifying eligible first-party source files, follow the SP Boucher Source Header
Policy. Preserve existing copyright and license notices, select the correct language-specific
template, and avoid adding identifying information to anonymous academic submission artifacts.

- Repository policy: `.spb-source-governance.toml` (project, contact, verified rights, license).
- Add or refresh headers with `spb-header apply --repo .`; verify with `spb-header check --repo .`.
- Never hand-write a header, never add one to generated, vendored, third-party or data files.
<!-- spb-source-governance:end -->
