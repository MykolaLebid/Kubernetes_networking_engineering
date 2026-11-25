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

Two complete courses + cheatsheets, published as a unified MkDocs-Material site named **"Platform Network Engineering"**.

### K8s Networking course — `lessons/` (39 files, lessons 00–38)
10 tracks (A–J), Theory/Practice split per lesson, Mermaid diagrams:
- A: Linux foundations (01–07) · B: CNI/eBPF (08–12) · C: K8s networking (13–16)
- D: Ingress/LB (17–20) · E: Service mesh (21–22) · F: Security (23–24)
- G: OpenShift (25–28) · H: AWS/EKS (29–32) · I: GitOps + AI/GPU (33–34)
- J: Security & Compliance (35–38): Tetragon, KubeEdge/edge, HIPAA/PCI-DSS/IEC 62443/GDPR, Multus CNI
- Lesson 00: visual overview
- `docs/ckne-prep.md` — CKNE + CCA cert exam prep guide
- `docs/cka-cks-prep.md` — CKA + CKS exam prep guide (domain → lesson map)
- `docs/compliance-paths.md` — sector-specific paths (medtech/banking/manufacturing/big tech, CH/DE/USA)

### CF Networking course — `docs/cf/` (23 files, cf-00 – cf-22)
Cloud Foundry / SAP BTP networking: Garden, Silk CNI, GoRouter, ASGs, Korifi, CF→K8s migration.
- Track CF-H (new): CF-21 Compliance (HIPAA/PCI-DSS/IEC 62443/GDPR), CF-22 SAP BTP Networking (Private Link, Cloud Connector, Kyma boundary)
- CF-07 and CF-15 enriched with compliance callout sections

### Cross-platform cheatsheets — `docs/cheatsheets/` (16 files, cs-00 – cs-15)
Side-by-side K8s vs CF comparisons, eBPF quick-ref, AWS EKS, OpenShift, AI/GPU networking.

### Other key files
- `manifests/` — YAML examples across lessons 12, 34, 35, 36, 37, 38 (NADs, TracingPolicies, compliance NetworkPolicies, SR-IOV, GPU pods)
- `labs/` — bash validation scripts: validate-10/12/21/34/38.sh + older validate-01/03/09/13/14/16/setup + README
- `docs/` — also contains: `index.md`, `k8s-overview.md`, `course-map.md`, `version-matrix.md`, `RESOURCES.md`, `shared/`, `migration/`
- `mkdocs.yml` — unified nav with tabs "K8s Networking" and "CF Networking"
- `render-pdf.sh` / `render-epub.sh` — K8s course PDF/EPUB (mmdc + pandoc + typst)
- `render-cf-pdf.sh` / `render-cf-epub.sh` — CF course PDF/EPUB
- `kubernetes-network-engineering.pdf/epub` — built K8s course artifacts
- `cf-networking.pdf/epub` — built CF course artifacts

## GitHub Pages

Site deploys automatically on push to `main` via GitHub Actions → `gh-pages` branch.
Live URL: https://mykolalibid.github.io/Kubernetes_networking_engineering/

## Two-terminal practice model

Every lesson assumes:
- Terminal 1: `minikube ssh` (Linux kernel commands)
- Terminal 2: Mac / local (kubectl, calicoctl, cilium, istioctl)
