# SPDX-License-Identifier: BSD-3-Clause
# Fetch helpers, flexbuild-style. Consumed by configs/components/*.mk.
#
#   $(call fetch_git,<name>,<url>,<rev-or-branch>)
#     fetches that rev/branch with FULL history (no shallow — we want usable git log) into src/<name> (GitHub allows
#     fetching arbitrary SHAs). Idempotent: skips if src/<name> exists.
#
#   $(call fetch_blob,<filename>)
#     ensures dl/<filename> exists: downloads from $(BLOB_BASE_URL)/<filename>
#     when set, else copies from the local AI SDK package ($(AISDK_BLOB_DIR)
#     fallback), then verifies against dl/SHA256SUMS.

SRC   := $(BSPDIR)/src
DLDIR := $(BSPDIR)/dl

# Optional remote host for the Renesas closed blobs (e.g. an internal server
# or a private GitHub release). When unset, fall back to the local AI SDK.
BLOB_BASE_URL ?=
AISDK_DIR ?= $(BSPDIR)/../yocto

define fetch_git
	@if [ -d $(SRC)/$(1) ]; then \
		echo "[INFO] $(1) already fetched"; \
	else \
		echo "[FETCH] $(1) <- $(2) @ $(3)"; \
		mkdir -p $(SRC)/$(1) && cd $(SRC)/$(1) && \
		git init -q && git remote add origin $(2) && \
		git fetch -q origin $(3) && \
		git checkout -q FETCH_HEAD && \
		git config user.name "Wig Cheng" && git config user.email "onlywig@gmail.com" && \
		echo "[INFO] $(1) HEAD: $$(git rev-parse HEAD)"; \
	fi
endef

define fetch_blob
	@if [ ! -f $(DLDIR)/$(1) ]; then \
		mkdir -p $(DLDIR); \
		if [ -n "$(BLOB_BASE_URL)" ]; then \
			echo "[FETCH] blob $(1) <- $(BLOB_BASE_URL)"; \
			wget -q -O $(DLDIR)/$(1) "$(BLOB_BASE_URL)/$(1)" || { rm -f $(DLDIR)/$(1); echo "[ERROR] download failed: $(1)"; exit 1; }; \
		elif [ -n "$(blob_$(1)_aisdk)" ] && [ -f "$(AISDK_DIR)/$(blob_$(1)_aisdk)" ]; then \
			echo "[FETCH] blob $(1) <- local AI SDK"; \
			cp "$(AISDK_DIR)/$(blob_$(1)_aisdk)" $(DLDIR)/$(1); \
		else \
			echo "[ERROR] blob $(1) unavailable: set BLOB_BASE_URL or provide AI SDK at $(AISDK_DIR)"; exit 1; \
		fi; \
	fi
	@cd $(DLDIR) && grep " \./$(1)$$" SHA256SUMS | sha256sum -c --quiet - \
		|| { echo "[ERROR] checksum mismatch: $(1)"; exit 1; }
endef
