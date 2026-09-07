# Trusted Firmware-A — roseapple-dev fork, managed like kernel/u-boot.
# Base = renesas-rz official snapshot tag 2.10.5/rzv2h_1.1.0 (3c83dd6f, the
# AI SDK v6.00 SRCREV; upstream publishes V2H only as history-less snapshot
# tags) + the Kakip BOARD=kakip_1 port (boot-verified on Kakip).
TFA_URL := git@github.com:roseapple-dev/kakip_trusted-firmware.git
TFA_REV := kakip-rz_v2.10_6.1.x-cip43-next

fetch-tfa:
	$(call fetch_git,trusted-firmware-a,$(TFA_URL),$(TFA_REV))
FETCH_TARGETS += fetch-tfa
