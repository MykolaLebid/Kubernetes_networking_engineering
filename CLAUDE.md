# CLAUDE.md — Kubernetes Network Engineering course repo

## Repository visibility: PUBLIC

This repository is public at https://github.com/MykolaLebid/Kubernetes_networking_engineering

**Never commit or include:**
- Personal credentials, tokens, passwords, or API keys
- Internal SAP hostnames, internal URLs, or internal IP ranges
- Personally identifiable information (names, emails, employee IDs)
- Any content marked confidential or restricted

All lesson content, manifests, lab scripts, and config files must be safe for public access.

## Project overview

34-lesson Kubernetes Network Engineering course. 9 tracks from Linux foundations to AI GPU platform networking.

- `lessons/` — 34 markdown lesson files
- `manifests/` — standalone ready-to-apply YAML examples per lesson
- `labs/` — bash validation scripts
- `docs/` — mkdocs-material site source (symlinks to lessons/ and RESOURCES.md)
- `mkdocs.yml` — site config; deploy via `.github/workflows/deploy.yml` to GitHub Pages
- `render-pdf.sh` — builds PDF with Mermaid diagrams rendered as PNGs (requires mmdc, pandoc, typst)

## GitHub Pages

Site deploys automatically on push to `main` via GitHub Actions → `gh-pages` branch.
Live URL: https://mykolalibid.github.io/Kubernetes_networking_engineering/

## Two-terminal practice model

Every lesson assumes:
- Terminal 1: `minikube ssh` (Linux kernel commands)
- Terminal 2: Mac / local (kubectl, calicoctl, cilium, istioctl)
