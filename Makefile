include pgxntool/base.mk

# TODO: Remove this after merging pgxntool 0.2.1+
testdeps: $(TEST_SQL_FILES) $(TEST_SOURCE_FILES)

#
# Test deps
#

test_core_files = $(wildcard $(TESTDIR)/core/*.sql)
testdeps: $(test_core_files) $(TESTDIR)/deps.sql

#
# OTHER DEPS
#
.PHONY: deps
deps: trunklet test_factory
testdeps: trunklet-format
install: deps

.PHONY: trunklet
trunklet: $(DESTDIR)$(datadir)/extension/trunklet.control
$(DESTDIR)$(datadir)/extension/trunklet.control:
	pgxn install 'trunklet>=0.2.0' --unstable

.PHONY: trunklet-format
trunklet-format: $(DESTDIR)$(datadir)/extension/trunklet-format.control
$(DESTDIR)$(datadir)/extension/trunklet-format.control:
	pgxn install 'trunklet-format>=0.2.0' --unstable

.PHONY: test_factory
test_factory: $(DESTDIR)$(datadir)/extension/test_factory.control
$(DESTDIR)$(datadir)/extension/test_factory.control:
	pgxn install test_factory

