include pgxntool/base.mk

# Need to manually strip control files out of $(DATA)
TMP := $(filter-out %.control,$(DATA))
DATA = $(TMP) $(CONTROLS)

# TODO: Remove this after merging pgxntool 0.2.1+
testdeps: $(TEST_SQL_FILES) $(TEST_SOURCE_FILES)

# .build directory
B := .build
EXTRA_CLEAN += $B
$B:
	mkdir -p $B

#
# CONTROL FILES
#
CONTROLS = $(EXTENSIONS:%=$B/%.control)
all: $(CONTROLS)
testdeps: $(CONTROLS)

# Deps
meta_deps: META.json meta_process.sh meta_funcs.sh

# Need 3 separate targets to support 3 cases...

# Case 1: there's simply a control file
$B/%.control: %.control | $B
	cp $< $@

# Case 2: there's a control.META file
$B/%.control: %.control.META meta_deps | $B
	./meta_process.sh -p "provides.$*" $< $@

# Case 3: Use default.control.META
$B/%.control: default.control.META meta_deps | $B
	./meta_process.sh -p "provides.$*" $< $@

#
# Test deps
#

test_core_files = $(wildcard $(TESTDIR)/core/*.sql)
testdeps: $(test_core_files) $(TESTDIR)/deps.sql

#
# OTHER DEPS
#
.PHONY: deps
deps: trunklet object_reference
testdeps: test_factory trunklet-format pgerror
install: deps

.PHONY: trunklet
trunklet: $(DESTDIR)$(datadir)/extension/trunklet.control
$(DESTDIR)$(datadir)/extension/trunklet.control:
	pgxn install 'trunklet>=0.2.0' --unstable

.PHONY: trunklet-format
trunklet-format: $(DESTDIR)$(datadir)/extension/trunklet-format.control
$(DESTDIR)$(datadir)/extension/trunklet-format.control:
	pgxn install 'trunklet-format>=0.2.0' --unstable

.PHONY: object_reference
object_reference: $(DESTDIR)$(datadir)/extension/object_reference.control
$(DESTDIR)$(datadir)/extension/object_reference.control:
	pgxn install object_reference

.PHONY: test_factory
test_factory: $(DESTDIR)$(datadir)/extension/test_factory.control
$(DESTDIR)$(datadir)/extension/test_factory.control:
	pgxn install test_factory

.PHONY: pgerror
pgerror: $(DESTDIR)$(datadir)/extension/pgerror.control
$(DESTDIR)$(datadir)/extension/pgerror.control:
	pgxn install pgerror

