# libcamera v0.8.0 from upstream, built in-chroot (tools/build_libcamera.sh)
LIBCAMERA_URL := https://gitlab.freedesktop.org/camera/libcamera.git
LIBCAMERA_REV := df8e348d64b4932a0676256ed24f0da3ee9438bc

fetch-libcamera:
	$(call fetch_git,libcamera,$(LIBCAMERA_URL),$(LIBCAMERA_REV))
FETCH_TARGETS += fetch-libcamera
