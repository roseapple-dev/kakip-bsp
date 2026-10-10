# Renesas closed blobs — no public source; cached in dl/ and verified against
# dl/SHA256SUMS. Source of truth today = local AI SDK package (AISDK_DIR);
# set BLOB_BASE_URL to fetch from a self-hosted server / private release
# instead (upload the dl/ contents there once).
#
# blob_<file>_aisdk = path inside $(AISDK_DIR) used as fallback.
AISDK_REC := RTK0EF0180F06000SJ_linux-src/rzv2h_ai-sdk_yocto_recipe_v6.00/meta-rz-features

blob_mali-g31_um_v1.3.0.tar.gz_aisdk := $(AISDK_REC)/meta-rz-graphics/recipes-graphics/mali/files/mali-g31_um_v1.3.0.tar.gz
blob_mali-g31_km_v1.3.0.tar.gz_aisdk := $(AISDK_REC)/meta-rz-graphics/recipes-kernel/kernel-module-mali/files/mali-g31_km_v1.3.0.tar.gz
blob_codec_pkg_product_v4.3.3.0.tar.gz_aisdk := $(AISDK_REC)/meta-rz-codecs/recipes-multimedia/codec-module/files/codec_pkg_product_v4.3.3.0.tar.gz
blob_uvcs_kernel_package_v4.3.3.0.tar.bz2_aisdk := $(AISDK_REC)/meta-rz-codecs/recipes-kernel/kernel-module-uvcs-drv/files/uvcs_kernel_package_v4.3.3.0.tar.bz2
blob_lib_tvm.tar.gz_aisdk := $(AISDK_REC)/meta-rz-drpai/recipes-core/lib-tvm/lib-tvm/lib_tvm.tar.gz
blob_libdrp_api.so_aisdk := $(AISDK_REC)/meta-rz-codecs/recipes-drp/drp-lib/files/libdrp_api.so
blob_Codec_Bin.bin_aisdk := $(AISDK_REC)/meta-rz-codecs/recipes-drp/drp-fw/files/Codec_Bin.bin
blob_OpenCV_Bin.bin_aisdk := $(AISDK_REC)/meta-rz-opencva/recipes-oca/oca/files/OpenCV_Bin.bin
blob_OMXR_VideoExt.h_aisdk := $(AISDK_REC)/meta-rz-codecs/recipes-multimedia/codec-module/files/OMXR_VideoExt.h
blob_OMXR_IndexExt.h_aisdk := $(AISDK_REC)/meta-rz-codecs/recipes-multimedia/codec-module/files/OMXR_IndexExt.h

BLOBS := mali-g31_um_v1.3.0.tar.gz mali-g31_km_v1.3.0.tar.gz \
         codec_pkg_product_v4.3.3.0.tar.gz uvcs_kernel_package_v4.3.3.0.tar.bz2 \
         OMXR_VideoExt.h OMXR_IndexExt.h \
         lib_tvm.tar.gz libdrp_api.so Codec_Bin.bin OpenCV_Bin.bin

define BLOB_template
fetch-blob-$(1):
	$$(call fetch_blob,$(1))
.PHONY: fetch-blob-$(1)
endef
$(foreach b,$(BLOBS),$(eval $(call BLOB_template,$(b))))

fetch-blobs: $(addprefix fetch-blob-,$(BLOBS))
FETCH_TARGETS += fetch-blobs
