# DRP-AI TVM runtime for RZ/V2H: renesas-rz/rzv_drp-ai_tvm v2.8.0-hotfix2 (MERA2).
# The repo ships the runtime only as prebuilt binaries (obj/build_runtime/v2h/lib,
# no source), so they are fetched file by file from the pinned commit and verified
# against dl/SHA256SUMS. Models must be compiled with the same DRP-AI TVM version.
# Needs the AI SDK v6.00 DRP-AI driver or later (kernel) and libmmngr/libmmngrbuf.
DRPAI_TVM_REV  := 63c44ef7f14dd240ec4e2aa315ee84d06807f243
DRPAI_TVM_URL  := https://raw.githubusercontent.com/renesas-rz/rzv_drp-ai_tvm/$(DRPAI_TVM_REV)
DRPAI_TVM_LIBS := libmera2_runtime.so libmera2_plan_io.so libdrp_tvm_rt.so libdrp_rt.so \
                  libacl_rt.so libarm_compute.so libarm_compute_core.so libarm_compute_graph.so \
                  log_out.bin rmsnorm_out.bin softmax_out.bin split_out.bin

fetch-drpai-tvm:
	@mkdir -p $(DLDIR)/drp-ai-tvm
	@cd $(DLDIR)/drp-ai-tvm && \
	for p in $(addprefix obj/build_runtime/v2h/lib/,$(DRPAI_TVM_LIBS)) LICENSE; do \
		f=$${p##*/}; [ -f $$f ] && continue; \
		echo "[FETCH] drp-ai-tvm/$$f <- rzv_drp-ai_tvm @ $(DRPAI_TVM_REV)"; \
		wget -q -O $$f "$(DRPAI_TVM_URL)/$$p" || { rm -f $$f; echo "[ERROR] download failed: $$f"; exit 1; }; \
	done
	@cd $(DLDIR) && grep " \./drp-ai-tvm/" SHA256SUMS | sha256sum -c --quiet - \
		|| { echo "[ERROR] checksum mismatch: drp-ai-tvm"; exit 1; }
.PHONY: fetch-drpai-tvm
FETCH_TARGETS += fetch-drpai-tvm
