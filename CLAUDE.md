# Lookbook

## Your Task

Write an implementation plan for the Lookbook macOS app. 

1. Read the design spec at `luts/docs/superpowers/specs/2026-03-10-lookbook-design.md`
2. Read the research doc at `luts/docs/research/2026-03-10-raw-lut-mac-app.md` for technical details
3. Write a detailed implementation plan to `luts/docs/superpowers/plans/2026-03-10-lookbook-plan.md`
4. The plan should break the build into ordered steps, each producing a working (or compilable) state
5. Each step should specify: what files to create/modify, what to implement, and how to verify it works
6. Commit and push the plan when done

## Key Context

- macOS 14+ SwiftUI app, no third-party dependencies
- CIRAWFilter for RAW decoding, CIColorCubeWithColorSpace for LUT application
- MTKView via NSViewRepresentable for GPU-backed preview
- Split right panel layout: edit sliders (left) + LUT browser with thumbnails (right)
- App name: Lookbook

## Commands

- git push origin main

## Important

- Do NOT write any Swift code — only write the implementation plan
- Be specific about API usage (CIRAWFilter properties, CIColorCubeWithColorSpace params, etc.)
- Reference the research doc for exact code patterns
