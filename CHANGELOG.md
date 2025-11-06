# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

## [](https://github.com/jacaudi/kiwix-helm-chart/releases/tag/) - 0001-01-01

- [`ff74d0c`](https://github.com/jacaudi/kiwix-helm-chart/commit/ff74d0c2b56b5078be30f39c86eac9d63707ea19) refactor: remove pushOptions from Uplift config
- [`a2cf896`](https://github.com/jacaudi/kiwix-helm-chart/commit/a2cf896a9b121b26376244d7f90a1533f6968aad) fix: add Chart.yaml to CI paths-ignore
- [`9ccfc91`](https://github.com/jacaudi/kiwix-helm-chart/commit/9ccfc91b88e5de3dba29ed7a90e3eebc679d938e) feat: add consolidated publish workflow with parallel jobs
- [`030a158`](https://github.com/jacaudi/kiwix-helm-chart/commit/030a158c82ab0d0f6d814e6123c0f563204e7420) Delete CHANGELOG.md
- [`96491b4`](https://github.com/jacaudi/kiwix-helm-chart/commit/96491b49db8c033acf058a04eab1d9ed93ba91c9) fix: update chart name to kiwix-helm-chart
- [`7b10355`](https://github.com/jacaudi/kiwix-helm-chart/commit/7b103556cb2a67b69ced837833a9dc730e5d0aef) refactor: split release workflow into separate file
- [`ca39ad8`](https://github.com/jacaudi/kiwix-helm-chart/commit/ca39ad89b159af19089e46627fd6dcaf5492bc2d) fix: ignore CHANGELOG.md updates in CI workflow
- [`3ef65c7`](https://github.com/jacaudi/kiwix-helm-chart/commit/3ef65c70e1bed2920ae806bafaed81d68edf0ee5) fix: update chart package name to kiwix-helm-chart
- [`9be21cc`](https://github.com/jacaudi/kiwix-helm-chart/commit/9be21cc2b88d4d97da1b75e0278e97436da07419) fix: specify chart path in OCI release action
- [`e62fa40`](https://github.com/jacaudi/kiwix-helm-chart/commit/e62fa40823dd76302105d28221151c5f154e0236) fix: add push options to uplift configuration for CI skipping
- [`442dc57`](https://github.com/jacaudi/kiwix-helm-chart/commit/442dc577ef4bfebf0e5eab1bdea9da6d369762e9) fix: use PAT instead of GITHUB_TOKEN for release workflow
- [`91dcf7a`](https://github.com/jacaudi/kiwix-helm-chart/commit/91dcf7a3aa79e81bbfdb20ac59c48b44e316f3d9) fix: correct release workflow to allow manual triggers
- [`c0f10b1`](https://github.com/jacaudi/kiwix-helm-chart/commit/c0f10b17beb24634e1b24ce4a69219523fd71105) feat: integrate Uplift for automated semantic versioning and releases (#1)
- [`2e6972b`](https://github.com/jacaudi/kiwix-helm-chart/commit/2e6972baea93c87326a9772682018f6ac391f64a) fix: correct capitalization in README.md for consistency
- [`9d9f698`](https://github.com/jacaudi/kiwix-helm-chart/commit/9d9f69832c641137daf91e5c869cdfadf14029f1) refactor: rename docker/ directory to image/
- [`5217b42`](https://github.com/jacaudi/kiwix-helm-chart/commit/5217b424cf4ec6be1203972ee2deb23781edeb44) Merge branch 'feature/kiwix-implementation'
- [`0b55d14`](https://github.com/jacaudi/kiwix-helm-chart/commit/0b55d140d1d5ce9230fd3b62cd6381b89b3aa292) feat: add Renovate GitHub Actions workflow
- [`5332292`](https://github.com/jacaudi/kiwix-helm-chart/commit/53322920e8b8fbfcd983b4ccdaae5d1ca930c1b6) feat: add Renovate configuration
- [`2078326`](https://github.com/jacaudi/kiwix-helm-chart/commit/20783268b2c98be569aae6294b7f02a87a413e65) fix: add missing common loader and CronJob support
- [`0a66e7e`](https://github.com/jacaudi/kiwix-helm-chart/commit/0a66e7e5cfc60e25536b7cc35fabe4dbe85f99a0) feat: add GitHub Actions workflow for Helm chart
- [`95b2a80`](https://github.com/jacaudi/kiwix-helm-chart/commit/95b2a80ce95a66b561546cbdaceaaecf344964de) feat: add GitHub Actions workflow for Docker image
- [`de621e8`](https://github.com/jacaudi/kiwix-helm-chart/commit/de621e85a5fa28285d3b50a6011f1ee9dc61744f) feat: add downloader script with retry and checksum logic
- [`1bce486`](https://github.com/jacaudi/kiwix-helm-chart/commit/1bce486d5bce665ba2182d90eeaa9c1ceb8b03f7) feat: add downloader Dockerfile
- [`389574f`](https://github.com/jacaudi/kiwix-helm-chart/commit/389574f000c3198f96cae126bcae2b3a70854cf7) Fix JSON quoting for sha256 values in ConfigMap
- [`ede2331`](https://github.com/jacaudi/kiwix-helm-chart/commit/ede23314a00733e518f33be3ee22207185ae6094) feat: add ConfigMap template for ZIM file URLs
- [`87cde4e`](https://github.com/jacaudi/kiwix-helm-chart/commit/87cde4e9fa279fb4bcd2278f0b377d7b5d161d13) feat: add chart foundation with bjw-s dependency
- [`9a448e4`](https://github.com/jacaudi/kiwix-helm-chart/commit/9a448e4bc5b89feef37b6c20ef0319a7f4b2606b) fix: update dependency from app-template to common library
- [`81eb5a6`](https://github.com/jacaudi/kiwix-helm-chart/commit/81eb5a66a447ffe7752df072c2a1c705defefeb8) fix: update username from acaudill to jacaudi in plan
- [`a7dfb0b`](https://github.com/jacaudi/kiwix-helm-chart/commit/a7dfb0bdb0c08e44ec8c6995df29d728497e9dce) Add .gitignore for worktrees directory
- [`4c4aec3`](https://github.com/jacaudi/kiwix-helm-chart/commit/4c4aec3e85e68a888fe99bbe96ecdc64e6195b92) Add Kiwix Helm chart design document
- [`3a6dc16`](https://github.com/jacaudi/kiwix-helm-chart/commit/3a6dc161baf780a82f122368c9b3cfe780050706) first commit
