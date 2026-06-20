# Build the runtime OpenSIPS config from the m4 template + site variables.
#
#   make            -> generate opensips.cfg
#   make check      -> generate, then validate with `opensips -C`
#   make install    -> copy opensips.cfg to $(DESTDIR)$(CFG_DIR)
#   make clean      -> remove generated opensips.cfg

M4       ?= m4
OPENSIPS ?= opensips
CFG_DIR  ?= /etc/opensips
DESTDIR  ?=

TEMPLATE := opensips.m4
LOCAL    := local.m4
OUT      := opensips.cfg

.PHONY: all check install clean

all: $(OUT)

$(OUT): $(LOCAL) $(TEMPLATE)
	$(M4) -P $(LOCAL) $(TEMPLATE) > $(OUT)
	@echo "Generated $(OUT). Validate with: make check"

check: $(OUT)
	$(OPENSIPS) -C -f $(OUT)

install: $(OUT)
	install -D -m 0640 $(OUT) $(DESTDIR)$(CFG_DIR)/$(OUT)

clean:
	rm -f $(OUT)
