# Linux kernel — roseapple-dev fork (base = Renesas rz-6.1-cip43 @10b3443b)
# AI SDK feature patches (dwmac/tx-lpi/mali) are baked into the fork as
# commits; DRP/codec not carried over. No build-time patching.
KERNEL_URL    := git@github.com:roseapple-dev/kakip_linux.git
KERNEL_REV    := kakip-rz-6.1.x-cip43-next

fetch-kernel:
	$(call fetch_git,linux,$(KERNEL_URL),$(KERNEL_REV))
FETCH_TARGETS += fetch-kernel
