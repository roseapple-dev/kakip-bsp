# rtl88x2bu — Realtek RTL8812BU/RTL8822BU USB WiFi vendor driver (88x2bu.ko),
#   e.g. EDUP EP-AC1686 (0bda:b812). RinCat's fork, the one the kakip_docs
#   EP-AC1686 guide uses. The repo has no tags, so pin a commit.
RTL88X2BU_URL := https://github.com/RinCat/RTL88x2BU-Linux-Driver.git
RTL88X2BU_REV := 465ae7cb522a382adc85ea5c31f228af8d172148

fetch-rtl88x2bu:
	$(call fetch_git,rtl88x2bu,$(RTL88X2BU_URL),$(RTL88X2BU_REV))
FETCH_TARGETS += fetch-rtl88x2bu
