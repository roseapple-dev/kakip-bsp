# Patch provenance

Patches originate from Renesas AI SDK v6.00
(RTK0EF0180F06000SJ_linux-src/rzv2h_ai-sdk_yocto_recipe_v6.00).

Only `mali-km/` is still applied at build time: the Mali KM source ships as a
closed blob tarball (`dl/mali-g31_km_v1.3.0.tar.gz`), not a git repo, so its
patches are applied by `tools/build_modules.sh` (quilt-style `series`).

| dir | Yocto recipe |
|---|---|
| mali-km/ | meta-rz-graphics kernel-module-mali_1.3.0.bb |

Every other component's AI SDK patches are now baked as commits into its
roseapple-dev fork (Renesas authorship preserved) — no in-repo patch dir;
see each fork's git history:

| former dir | fork |
|---|---|
| linux/ (incl. DRP/codec/drpai) | kakip_linux |
| mmngr/ mmngrbuf/ | mmngr_drv |
| vspm/ (base + ISU; rzg3e-only dropped) | vspm_drv |
| vspmif-drv/ | vspmif_drv |
| vspmif-lib/ | vspmif_lib |
| vspmfilter/ | vspmfilter |

DRP/codec and rzg3e-only patches were intentionally not carried into any fork
(V2H doesn't use them); re-derive from the AI SDK tree if ever needed.
