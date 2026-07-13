# CLAUDE.md

Guidance for AI assistants (and humans) working in this repository.

## What this is

`github-slideshow` is a **Jekyll site that renders a [reveal.js](https://github.com/hakimel/reveal.js) slide deck**. It originated as the sample repository for the GitHub Learning Lab "Introduction to GitHub" course, so its primary purpose is teaching Git/GitHub workflows (branches, commits, pull requests) — the slideshow itself is the deliverable students build and publish via GitHub Pages.

There is **no application code, test suite, or backend**. "Building" means running Jekyll to turn Markdown posts + Liquid templates into a static `_site/` directory. Keep changes small and content-focused unless asked otherwise.

## Tech stack

- **Jekyll** (via the `github-pages` gem) — static site generator, hosted on GitHub Pages
- **Liquid** — templating language used in layouts and includes
- **reveal.js 3.9.2** — the HTML presentation framework (vendored in `node_modules/`)
- **Ruby / Bundler** — dependency management (`Gemfile`, `Gemfile.lock`)
- **kramdown** — Markdown processor; **rouge** — syntax highlighter; **jemoji** — emoji plugin
- **html-proofer** — link/HTML validation in CI

## Repository layout

```
_config.yml        Jekyll + reveal.js configuration (site metadata, reveal options, excludes)
index.html         Home page — loops over _posts to emit one slide per post
_posts/            Slide content. One Markdown file = one slide.
_layouts/          Page-level Liquid templates (presentation, print, slide)
_includes/         Reusable Liquid partials (head, script, slide)
script/            Executable dev scripts (setup, server, cibuild, stage)
node_modules/      Vendored reveal.js assets (referenced by templates; NOT built by npm)
Gemfile[.lock]     Ruby gem dependencies
_config.yml        Site + reveal.js settings
README.md          Learning Lab course intro (not dev docs)
```

## How the slideshow is assembled

1. `_config.yml` sets site-wide options, including the full `reveal:` block that configures the presentation (transitions, controls, dimensions, etc.).
2. `index.html` uses layout `presentation` and iterates `site.posts reversed`, rendering `_includes/slide.html` for each post plus a `<div class="page-break">`.
3. `_layouts/presentation.html` wraps everything in the reveal.js `.reveal > .slides` structure, pulls in `_includes/head.html` (stylesheets, viewport, PDF-print logic) and `_includes/script.html` (loads `reveal.js` and calls `Reveal.initialize`).
4. `_includes/slide.html` renders each post as a `<section class="step ...">`, honoring optional post front matter: `slide-id`, `classes`, `data` (for reveal data-attributes), and `title`.

### Adding or editing a slide

Create a Markdown file in `_posts/` following Jekyll's naming convention:

```
_posts/YYYY-MM-DD-title.md
```

Slides render in **reverse chronological order** (`site.posts reversed` in `index.html`), so the **date in the filename controls slide order**. The existing intro slide uses `0000-01-01-intro.md` to sort first. Front matter drives rendering:

```markdown
---
layout: slide
title: "Slide heading"      # rendered as <h1>; use title: "" to omit
slide-id: my-anchor         # optional: id attribute for the <section>
classes: [cover, dark]      # optional: extra CSS classes (defaults to "slide")
---

Slide body in Markdown.
```

## Development workflow

Scripts live in `script/` and follow the [Scripts to Rule Them All](https://github.com/github/scripts-to-rule-them-all) pattern. Run them from the repo root.

| Command          | Purpose                                                                 |
| ---------------- | ----------------------------------------------------------------------- |
| `script/setup`   | Install Ruby gem dependencies via Bundler (and rbenv/Homebrew if present); inits git submodules. |
| `script/server`  | Run Jekyll locally with live reload: `bundle exec jekyll serve`. Extra args pass through. |
| `script/cibuild` | Build with `--baseurl "."` then validate output with `htmlproofer` (`--empty-alt-ignore`). |
| `script/stage`   | Build with a staging baseurl and force-push `_site` to an internal GitHub Enterprise Pages remote. Legacy/internal — not needed for normal work. |

Typical loop:

```sh
script/setup          # once, or after Gemfile changes
script/server         # preview at http://localhost:4000
```

Before pushing, mirror CI locally:

```sh
script/cibuild
```

## Conventions

- **Indentation (`.editorconfig`):** tabs (width 4) by default; **2 spaces** for `json/js/css/scss/yml/htm/html`; 4 spaces for Markdown. Respect `trim_trailing_whitespace` and note `insert_final_newline = false` for non-Markdown files (Markdown files DO get a final newline).
- **Templating:** logic lives in `_layouts/` and `_includes/`; content lives in `_posts/`. Prefer editing includes over duplicating markup.
- **reveal.js assets** are vendored under `node_modules/reveal.js` and referenced directly by `_includes/head.html` and `_includes/script.html`. `package-lock.json` pins the version (3.9.2); there is no `package.json` build step — do not expect `npm install` to be part of the flow.
- **Generated output** (`_site/`, `.sass-cache/`, `.jekyll-metadata`, `.bundle`) is git-ignored; never commit it.
- **Reveal/site config** is centralized in `_config.yml`. Change presentation behavior (transition, controls, slide numbers, theme) there rather than in templates.

## CI / deployment

- GitHub Pages builds and serves the site from the default branch automatically.
- `script/cibuild` is the canonical build+validate check: `jekyll build` followed by `htmlproofer`. Keep links valid and avoid broken HTML so html-proofer passes.
- `_config.yml` `exclude:` list keeps `Gemfile*`, `vendor`, and stray reveal.js files out of the build.

## Working in this repo (for AI assistants)

- This repo is primarily educational content. Default to **minimal, content-focused edits**; don't introduce build tooling, frameworks, or restructuring unless explicitly requested.
- When adding slides, follow the `_posts/YYYY-MM-DD-title.md` convention and remember date ordering is reversed.
- Validate changes with `script/cibuild` when possible before committing.
- Follow `.editorconfig` for whitespace — it varies by file type.
- Do not commit `_site/` or other generated artifacts.
