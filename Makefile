include pgxntool/base.mk

#
# Test deps
#

test_core_files = $(wildcard $(TESTDIR)/core/*.sql)
testdeps: $(test_core_files)

#
# OTHER DEPS
#
.PHONY: deps
deps: trunklet

install: deps

.PHONY: trunklet
trunklet: $(DESTDIR)$(datadir)/extension/trunklet.control

$(DESTDIR)$(datadir)/extension/trunklet.control:
	pgxn install trunklet --unstable
