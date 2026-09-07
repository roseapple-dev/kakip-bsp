# mmngr / mmngrbuf — kernel drv + user lib.
# mmngr_drv: roseapple fork = renesas-rcar + AI SDK patch/mmngr{,buf} series
#   baked in as commits (no build-time patching; see build_modules.sh).
# mmngr_lib: still upstream renesas-rcar (userspace, unpatched).
MMNGR_DRV_URL := git@github.com:roseapple-dev/mmngr_drv.git
MMNGR_DRV_REV := kakip_renesas-6.1.141-next
MMNGR_LIB_URL := https://github.com/renesas-rcar/mmngr_lib.git
MMNGR_LIB_REV := 0322548e54b45a064c9cecea29018ef50cdb8423

fetch-mmngr:
	$(call fetch_git,mmngr_drv,$(MMNGR_DRV_URL),$(MMNGR_DRV_REV))
	$(call fetch_git,mmngr_lib,$(MMNGR_LIB_URL),$(MMNGR_LIB_REV))
FETCH_TARGETS += fetch-mmngr
