# vspm / vspmif — kernel drvs + user lib.
# All three are roseapple forks with their AI SDK patches baked in as commits
# (no build-time patching). vspm_drv = base + ISU (19; rzg3e-only dropped),
# vspmif_drv = base + ISU (7), vspmif_lib = ISU (6).
VSPM_DRV_URL   := git@github.com:roseapple-dev/vspm_drv.git
VSPM_DRV_REV   := kakip_renesas-6.1.141-next
VSPMIF_DRV_URL := git@github.com:roseapple-dev/vspmif_drv.git
VSPMIF_DRV_REV := kakip_renesas-6.1.141-next
VSPMIF_LIB_URL := git@github.com:roseapple-dev/vspmif_lib.git
VSPMIF_LIB_REV := kakip_renesas-6.1.141-next

fetch-vspm:
	$(call fetch_git,vspm_drv,$(VSPM_DRV_URL),$(VSPM_DRV_REV))
	$(call fetch_git,vspmif_drv,$(VSPMIF_DRV_URL),$(VSPMIF_DRV_REV))
	$(call fetch_git,vspmif_lib,$(VSPMIF_LIB_URL),$(VSPMIF_LIB_REV))
FETCH_TARGETS += fetch-vspm
