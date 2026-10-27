# Slide maintenance

Read PUBLIC_CONTENT_GUIDELINES_zh-TW.md and README.md before editing this guide.
The guidelines are a generated copy of the common /web root policy.
Keep its neutral sharing tone, current-state wording and source/evidence rules.

- This page owns MCU CAN device Boot/App, metadata, vector and porting topics.
- F13/F24 device Boot/App are joint golden samples. Both use editable C headers
  for image/IRQ settings; preserve common authoring/generation/validation for
  future MCU ports. Project-specific rules stay here, not in /web root policy.
- Edit the canonical Tool docs first; use their sync scripts and -CheckOnly.
- Preserve stable anchors and use short links to ISP-owned topics.
- index.md is the short overview,not a destination for full chapters. Tool
  scripts/web_guide_layout.json owns marker-to-page placement. Preserve the
  guide-map.json legacy aliases;refresh generated guide-routes.js after adding
  stable anchors. Flat HTML/MD chapters retain existing relative assets.
- The page-owned DEVICE_MODE_NAV groups F13/F24 Classical CAN together and
  F24 CAN FD separately,plus Custom Transfer across all three examples;
  link engineering/update/Transfer chapters,not copies.
- Update affected PDFs; keep commands, byte values and safety gates unchanged
  during editorial changes. Do not rebuild firmware or bump the Tool version.
- Never infer Git publication or hardware acceptance from local synchronization.
- Run the ISP scripts/verify_local.ps1 with -ToolRoot for cross-page checks.
- Keep six chapter titles/order and60 topic counterparts aligned with RH850
  through Tool scripts/bootloader_guide_contract.json. Platform values remain
  source-specific;both homepages link directly to their existing timing table.
