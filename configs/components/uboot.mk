# U-Boot — roseapple-dev fork (HEAD == AI SDK SRCREV 8e0b7870)
UBOOT_URL    := git@github.com:roseapple-dev/kakip_u-boot.git
UBOOT_REV    := kakip-rz_v2024.07_rzv2h_1.1.0-next
UBOOT_CONFIG := rzv2h-evk-ver1_defconfig

fetch-uboot:
	$(call fetch_git,u-boot,$(UBOOT_URL),$(UBOOT_REV))
FETCH_TARGETS += fetch-uboot
