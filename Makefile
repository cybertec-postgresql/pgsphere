
include Makefile.common.mk

RELEASE_SQL      = $(EXTENSION)--$(PGSPHERE_VERSION).sql
USE_PGXS         = 1
USE_HEALPIX      =? 1

# the base dir name may be changed depending on git clone command
SRC_DIR = $(shell basename $(shell pwd))

MODULE_big = pg_sphere
OBJS       = src/sscan.o src/sparse.o src/sbuffer.o src/vector3d.o src/point.o \
             src/euler.o src/circle.o src/line.o src/ellipse.o src/polygon.o \
             src/path.o src/box.o src/output.o src/gq_cache.o src/gist.o \
             src/key.o src/gnomo.o src/epochprop.o src/brin.o

ifneq ($(USE_HEALPIX),0)
OBJS      += src/healpix.o src/moc.o src/process_moc.o \
             healpix_bare/healpix_bare.o
endif

DATA_built  = $(RELEASE_SQL) \
			  pg_sphere--1.2.0--1.2.1.sql \
			  pg_sphere--1.2.1--1.2.2.sql \
			  pg_sphere--1.2.2--1.2.3.sql \
			  pg_sphere--1.2.3--1.3.0.sql \
			  pg_sphere--1.3.0--1.3.1.sql \
			  pg_sphere--1.3.1--1.3.2.sql

DOCS        = README.pg_sphere COPYRIGHT.pg_sphere
REGRESS     = init tables points euler circle line ellipse poly path box index \
              contains_ops contains_ops_compat bounding_box_gist gnomo epochprop \
              contains overlaps spoint_brin sbox_brin

TESTS       = init_test tables points euler circle line ellipse poly path box \
              index contains_ops contains_ops_compat bounding_box_gist gnomo \
              epochprop contains overlaps spoint_brin sbox_brin

PG_CFLAGS	+= -DPGSPHERE_VERSION=$(PGSPHERE_VERSION)
PG_CPPFLAGS	+= -DPGSPHERE_VERSION=$(PGSPHERE_VERSION)

ifndef CXXFLAGS
# no support for CXXFLAGS in PGXS before v11
CXXFLAGS = -Wall -Wpointer-arith -Wendif-labels \
		-Wmissing-format-attribute -Wformat-security -g -O2 -fPIC
endif

EXTRA_CLEAN = $(PGS_SQL) pg_sphere.test.sql

CRUSH_TESTS = init_extended circle_extended

# order of sql files is important
PGS_SQL     = pgs_types.sql pgs_point.sql pgs_euler.sql pgs_circle.sql \
              pgs_line.sql pgs_ellipse.sql pgs_polygon.sql pgs_path.sql \
              pgs_box.sql pgs_contains_ops.sql pgs_contains_ops_compat.sql \
              pgs_gist.sql gnomo.sql pgs_brin.sql

ifneq ($(USE_HEALPIX),0)
REGRESS    += healpix moc moc1 moc100 mocautocast
TESTS      += healpix moc moc1 moc100 mocautocast
PGS_SQL    += healpix.sql
endif

PGS_SQL    += pgs_gist_spoint3.sql

ifneq ($(USE_HEALPIX),0)
PGS_SQL    += pgs_moc_type.sql pgs_moc_compat.sql pgs_moc_ops.sql \
              pgs_moc_geo_casts.sql
endif

PGS_SQL    += pgs_epochprop.sql

ifdef USE_PGXS
  ifndef PG_CONFIG
    PG_CONFIG = pg_config
  endif
  PGXS := $(shell $(PG_CONFIG) --pgxs)
  include $(PGXS)
else
  subdir = contrib/pg_sphere
  top_builddir = ../..
  PG_CONFIG := $(top_builddir)/src/bin/pg_config/pg_config
  include $(top_builddir)/src/Makefile.global
  include $(top_srcdir)/contrib/contrib-global.mk
endif

ifneq ($(USE_HEALPIX),0)
# compiler settings for linking with libhealpix_cxx
PKG_CONFIG ?= pkg-config
override CPPFLAGS += $(shell $(PKG_CONFIG) --cflags healpix_cxx)
SHLIB_LINK += $(shell $(PKG_CONFIG) --libs healpix_cxx)
LINK.shared = g++ -shared
endif

# healpix_bare.c isn't ours so we refrain from fixing the warnings in there
healpix_bare/healpix_bare.o : healpix_bare/healpix_bare.c
	$(COMPILE.c) -Wno-declaration-after-statement -o $@ $^

pg_version := $(word 2,$(shell $(PG_CONFIG) --version))

crushtest: REGRESS += $(CRUSH_TESTS)
crushtest: installcheck

test: pg_sphere.test.sql
	$(pg_regress_installcheck) --temp-instance=tmp_check $(REGRESS_OPTS) $(TESTS)

pg_sphere.test.sql: $(RELEASE_SQL) $(shlib)
	tail -n+3 $< | sed 's,MODULE_PATHNAME,$(realpath $(shlib)),g' >$@

$(RELEASE_SQL): pg_sphere_head.sql.in $(addsuffix .in, $(PGS_SQL))
	cat $^ > $@

ifneq ($(USE_HEALPIX),0)
pg_sphere--1.2.0--1.2.1.sql: pgs_moc_geo_casts.sql.in pgs_epochprop.sql.in
	cat upgrade_scripts/$@.in $^ > $@

pg_sphere--1.2.1--1.2.2.sql: upgrade_scripts/pg_sphere--1.2.1--1.2.2-healpix.sql.in
	cat upgrade_scripts/$@.in $^ > $@
else
pg_sphere--1.2.0--1.2.1.sql: pgs_epochprop.sql.in
	cat upgrade_scripts/$@.in $^ > $@

pg_sphere--1.2.1--1.2.2.sql:
	cat upgrade_scripts/$@.in > $@
endif

pg_sphere--1.2.2--1.2.3.sql:
	cat upgrade_scripts/$@.in > $@

pg_sphere--1.2.3--1.3.0.sql: pgs_brin.sql.in
	cat upgrade_scripts/$@.in $^ > $@

pg_sphere--1.3.0--1.3.1.sql:
	cat upgrade_scripts/$@.in > $@

pg_sphere--1.3.1--1.3.2.sql:
	cat upgrade_scripts/$@.in > $@

# end of local stuff

src/sscan.o : src/sparse.c

src/sparse.c: src/sparse.y
ifdef YACC
	$(YACC) -d $(YFLAGS) -p sphere_yy -o $@ $<
else
	@$(missing) bison $< $@
endif

src/sscan.c : src/sscan.l
ifdef FLEX
	$(FLEX) $(FLEXFLAGS) -Psphere -o$@ $<
else
	@$(missing) flex $< $@
endif

dist : clean sparse.c sscan.c
	find . -name '*~' -type f -exec rm {} \;
	cd .. && tar --transform s/$(SRC_DIR)/pgsphere-$(PGSPHERE_VERSION)/ --exclude CVS --exclude .git -czf pgsphere-$(PGSPHERE_VERSION).tar.gz $(SRC_DIR) && cd -
