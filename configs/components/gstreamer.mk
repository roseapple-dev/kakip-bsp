# Renesas GStreamer plugins (rebuilt in-chroot against Ubuntu's GStreamer)
# gst-omx: gstreamer1.0-omx_1.22.12.bbappend (branch RZ/1.22.12)
# vspmfilter: roseapple fork = rzg_gstreamer_vspmfilter + the AI SDK VTOP
#   patch baked in as a commit (no build-time patching).
GSTOMX_URL     := https://github.com/renesas-rz/gst-omx.git
GSTOMX_REV     := 189acf4df3f6328593566a0e36b86997111d9ccc
VSPMFILTER_URL := git@github.com:roseapple-dev/vspmfilter.git
VSPMFILTER_REV := kakip_renesas-6.1.141-next

fetch-gst:
	$(call fetch_git,gst-omx,$(GSTOMX_URL),$(GSTOMX_REV))
	$(call fetch_git,vspmfilter,$(VSPMFILTER_URL),$(VSPMFILTER_REV))
FETCH_TARGETS += fetch-gst
