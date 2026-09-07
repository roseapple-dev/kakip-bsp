# Kakip Ubuntu 26.04 GNOME BSP
# flexbuild-style: per-component pins in configs/components/*.mk, fetch
# helpers in include/download.mk, vendored patches in patch/<comp>/series.
# To bump a component: edit its .mk (URL/REV) and adjust patch/<comp>/.

BSPDIR := $(CURDIR)
include $(BSPDIR)/include/download.mk
include $(wildcard $(BSPDIR)/configs/components/*.mk)

BUILD  := $(BSPDIR)/build
ROOTFS_TAR := $(BUILD)/rootfs.tar
IMG    := $(BUILD)/kakip-ubuntu-26.04-gnome-arm64.img

.PHONY: all fetch $(FETCH_TARGETS) kernel modules bootloader rootfs image clean distclean

all: image

fetch: $(FETCH_TARGETS)

kernel:
	@bash tools/build_kernel.sh

modules:
	@bash tools/build_modules.sh

# Kakip always builds from source (u-boot 2024.07 + TF-A 2.10, kakip_1);
# the prebuilt-EVK path is legacy — call the script bare to use it.
bootloader:
	@bash tools/build_bootloader.sh --from-source

# fully rootless: mmdebstrap unshare + hooks (post-config & gst build inside)
rootfs:
	@bash configs/ubuntu/ubuntu_desktop_arm64.sh $(ROOTFS_TAR)

image:
	@bash tools/create_image.sh $(ROOTFS_TAR) $(IMG)

# release artifact: fresh-mke2fs free blocks are sparse zeros → xz crushes it
image-xz: image
	xz -f -T0 -9 -k $(IMG)
	@ls -la $(IMG).xz

define check_removable
own=$$(find $(1) -xdev ! -user $$(id -un) -print -quit 2>/dev/null); \
if [ -n "$$own" ] && [ "$$(id -u)" != 0 ]; then \
  echo "$(2): $$own is owned by $$(stat -c %U "$$own"); run it inside the build container:"; \
  echo "  docker exec -w /home/mnt$(subst $(HOME),,$(BSPDIR)) 26.04-build make $(2)"; \
  echo "  (or: sudo make $(2))"; exit 1; \
fi
endef

clean:
	@$(call check_removable,$(BUILD),clean)
	rm -rf $(BUILD)
	@echo "clean: removed build/"

distclean:
	@nf=; for d in $(SRC)/*/; do \
	  [ -e "$$d/.git" ] || continue; \
	  s=$$(git -C "$$d" status --porcelain --untracked-files=no 2>/dev/null) || { nf=1; break; }; \
	  [ -z "$$s" ] || { nf=1; break; }; \
	done; \
	if [ "$$nf" = 1 ] && [ "$(FORCE)" != 1 ]; then \
	  echo "distclean: src/ has uncommitted tracked changes not in the forks."; \
	  echo "  commit/push first, or force: make distclean FORCE=1"; \
	  exit 1; \
	fi
	@$(call check_removable,$(BUILD) $(SRC) $(DLDIR),distclean)
	rm -rf $(BUILD) $(SRC)
	find $(DLDIR) -mindepth 1 ! -name SHA256SUMS -delete
	@echo "distclean: removed build/ + src/ + dl/* (kept dl/SHA256SUMS)"
