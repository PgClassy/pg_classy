include pgxntool/base.mk

#
# OTHER DEPS
#
.PHONY: deps
deps: trunklet

install: deps

.PHONY: trunklet
trunklet: $(DESTDIR)$(datadir)/extension/variant.control

$(DESTDIR)$(datadir)/extension/trunklet.control:
	pgxn install trunklet --unstable
