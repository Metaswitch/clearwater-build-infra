# Common C++ Makefile infrastructure
#
# Product specific Makefiles define a list of TARGETS and TEST_TARGETS
# and then `include` this Makefile.  To customise the build product
# Makefiles can define the following to tweak the behavior:
#
#   <target>_SOURCES  - List the .cpp files to build (defaults to target.cpp only)
#   <target>_CPPFLAGS - Specific flags to pass to the C++ compiler
#   <target>_LDFLAGS  - Specific flags to pass to the linker
#
# For test targets, there are a few extra customization flags:
#
#   <target>_VALGRIND_ARGS - Extra, product specific arguments for Valgrind
#
# This Makefile snippet defines a few variables that may be useful when adding
# extra pre-requisites to targets:
#
#   CLEANS              - All files listed in this will be removed by `make clean`
#   CLEAN_DIRS          - All directories listed in this will be removed by `make clean`

.DEFAULT_GOAL := all
.PHONY : all test full_test valgrind valgrind_check coverage_check coverage_raw clean

# Makefiles can override these if needed
ROOT ?= ..
GMOCK_DIR ?= ${ROOT}/modules/gmock
GTEST_DIR ?= ${GMOCK_DIR}/gtest
GCOVR_DIR ?= ${ROOT}/modules/gcovr
CPP_COMMON_DIR ?= ${ROOT}/modules/cpp-common
BUILD_DIR ?= ${ROOT}/build

# Common rules to build any target
#
# @param $1 - Target name (final executable)
# @param $2 - Build flavor (valid values are `test` or `release`)
define common_target

# Calculate the object names for the $1 build
$1_OBJS := $$(patsubst %.cpp,$${BUILD_DIR}/$1/%.o,$${$1_SOURCES})
$1_DEPS := $$(patsubst %.cpp,$${BUILD_DIR}/$1/%.d,$${$1_SOURCES})

# Create alias for the object directory this allows the parent Makefile
# to add extra pre-requisites to specific objects (e.g. auto-generated
# header files)
$1_OBJECT_DIR := $${BUILD_DIR}/$1

# Object files are produced by compiling source files
$${$1_OBJS} : $${$1_OBJECT_DIR}/%.o : %.cpp
	@mkdir -p $${$1_OBJECT_DIR}
	${CXX} ${CXXFLAGS} ${CPPFLAGS} -MMD -MP $${$2_CPPFLAGS} $${$1_CPPFLAGS} -c $$< -o $$@

# Final linker step for $1
$${BUILD_DIR}/bin/$1 : $${$1_OBJS}
	@mkdir -p $${BUILD_DIR}/bin/
	${CXX} ${LDFLAGS} -o $$@ $$^ $${$2_LDFLAGS} $${$1_LDFLAGS}

# Shortcut alias to make $1
.PHONY : $1
$1 : $${BUILD_DIR}/bin/$1

# Include depends files from $1
DEPENDS += $${$1_DEPS}}

# Clean up for $1
CLEANS += $${BUILD_DIR}/bin/$1
CLEAN_DIRS += $${$1_OBJECT_DIR}

endef

# Extra rules for TEST_TARGETS
#
# @param $1 - Target name (final executable)
define test_target

# Call into standard build infrastructure for $1
$(call common_target,$1,test)

$${BUILD_DIR}/bin/$1 : $${BUILD_DIR}/obj/gmock-all.o $${BUILD_DIR}/obj/gtest-all.o

.PHONY : run_$1
run_$1 : $${BUILD_DIR}/bin/$1
	LD_LIBRARY_PATH=${ROOT}/usr/lib/ $$< ${EXTRA_TEST_ARGS}

# This sentinel file proves the tests have *all* been run on this build (mostly for coverage)
$${BUILD_DIR}/$1/.$1_already_run : $${BUILD_DIR}/bin/$1
	LD_LIBRARY_PATH=${ROOT}/usr/lib/ $$< --gtest_output=xml:$${BUILD_DIR}/$1/gtest_output.xml
	@touch $$@

.PHONY : debug_$1
debug_$1 : $${BUILD_DIR}/bin/$1
	LD_LIBRARY_PATH=${ROOT}/usr/lib/ gdb --args $$< $${EXTRA_TEST_ARGS}

# Valgrind arguments for $1
$1_VALGRIND_ARGS += --gen-suppressions=all --leak-check=full --track-origins=yes --malloc-fill=cc --free-fill=df

$${BUILD_DIR}/$1/valgrind_output.xml : $${BUILD_DIR}/bin/$1
	LD_LIBRARY_PATH=${ROOT}/usr/lib/ valgrind $${$1_VALGRIND_ARGS} --xml=yes --xml-file=$$@ $$< --gtest_filter="-*DeathTest*"

.PHONY : valgrind_check_$1
valgrind_check_$1 : $${BUILD_DIR}/$1/valgrind_output.xml
	@mkdir -p $${BUILD_DIR}/scratch/
	@xmllint --xpath '//error/kind' $$< 2>&1 | \
		sed -e 's#<kind>##g' | \
		sed -e 's#</kind>#\n#g' | \
		sort > $${BUILD_DIR}/scratch/valgrind.tmp
	@if grep -q -v "XPath set is empty" $${BUILD_DIR}/scratch/valgrind.tmp ; then \
		echo "Error: some memory errors have been detected" ; \
		cat $${BUILD_DIR}/scratch/valgrind.tmp ; \
		echo "See $$< for further details." ; \
		exit 2 ; \
	fi

CLEANS += $${BUILD_DIR}/scratch/valgrind.tmp

.PHONY : valgrind_$1
valgrind_$1 : $${BUILD_DIR}/bin/$1
	LD_LIBRARY_PATH=${ROOT}/usr/lib/ valgrind $${$1_VALGRIND_ARGS} $$< $${EXTRA_TEST_ARGS}

# Coverage arguments for $1
COMMON_COVERAGE_EXCLUSIONS := ^ut|^$${GMOCK_DIR}
ifdef $1_COVERAGE_EXCLUSIONS
	COVERAGE_EXCLUSIONS := $${COMMON_COVERAGE_EXCLUSIONS}|$${$1_COVERAGE_EXCLUSIONS}
else
	COVERAGE_EXCLUSIONS := $${COMMON_COVERAGE_EXCLUSIONS}
endif

REAL_OBJECT_DIR := $(realpath ${BUILD_DIR}/$1)
$1_COVERAGE_ARGS := --root=$(shell pwd) --exclude="$${COVERAGE_EXCLUSIONS}" $${REAL_OBJECT_DIR}

$${BUILD_DIR}/$1/coverage.xml : $${BUILD_DIR}/$1/.$1_already_run
	@${GCOVR_DIR}/scripts/gcovr $${$1_COVERAGE_ARGS} --xml > $$@ || (rm $$@; exit 2)

.PHONY : coverage_check_$1
coverage_check_$1 : $${BUILD_DIR}/$1/coverage.xml
	@mkdir -p $${BUILD_DIR}/scratch/
	@xmllint --xpath '//class[@line-rate!="1.0"]/@filename' $$< \
		| tr ' ' '\n' \
		| grep filename= \
		| cut -d\" -f2 \
		| sort > $${BUILD_DIR}/scratch/coverage_$1.tmp
	@sort ut/coverage-not-yet | comm -23 $${BUILD_DIR}/scratch/coverage_$1.tmp - > $${BUILD_DIR}/scratch/coverage_$1_filtered.tmp
	@if grep -q ^ $${BUILD_DIR}/scratch/coverage_$1_filtered.tmp ; then \
		echo "Error: some files unexpectedly have less than 100% code coverage:" ; \
		cat $${BUILD_DIR}/scratch/coverage_$1_filtered.tmp ; \
		exit 2 ; \
	fi
CLEANS += $${BUILD_DIR}/scratch/coverage_$1.tmp $${BUILD_DIR}/scratch/coverage_$1_filtered.tmp

.PHONY : coverage_raw_$1
coverage_raw_$1 : $${BUILD_DIR}/$1/.$1_already_run
	@${GCOVR_DIR}/scripts/gcovr $${$1_COVERAGE_ARGS} --keep --sort-percentage

test : run_$1
valgrind : valgrind_$1
valgrind_check : valgrind_check_$1
coverage_check : coverage_check_$1
coverage_raw : coverage_raw_$1

CLEANS += $${BUILD_DIR}/$1/valgrind_output.xml $${BUILD_DIR}/$1/.$1_already_run

endef

# Default values for build flags for each build
__COMMON_CPPFLAGS := -ggdb3 -std=c++11 -Wall -Werror
release_CPPFLAGS := -O2 ${__COMMON_CPPFLAGS}
test_CPPFLAGS := -O0 ${__COMMON_CPPFLAGS} -DUNIT_TEST \
                 -fprofile-arcs -ftest-coverage \
                 -fno-access-control \
                 -I${GTEST_DIR}/include -I${GMOCK_DIR}/include \
                 -I${CPP_COMMON_DIR}/test_utils
test_LDFLAGS := -lgcov --coverage

ifdef JUSTTEST
  EXTRA_TEST_ARGS ?= --gtest_filter=*$(JUSTTEST)*
endif

${BUILD_DIR}/obj/gmock-all.o : ${GMOCK_DIR}/src/gmock-all.cc ${GMOCK_DIR}/include/gmock/*.h ${GMOCK_DIR}/include/gmock/internal/*.h
	@mkdir -p ${BUILD_DIR}/obj
	${CXX} ${test_CPPFLAGS} -I${GTEST_DIR}/include -I${GMOCK_DIR}/include -I${GMOCK_DIR} -c $< -o $@
${BUILD_DIR}/obj/gtest-all.o : ${GTEST_DIR}/src/gtest-all.cc ${GTEST_DIR}/include/gtest/*.h ${GTEST_DIR}/include/gtest/internal/*.h
	@mkdir -p ${BUILD_DIR}/obj
	${CXX} ${test_CPPFLAGS} -I${GTEST_DIR}/include -I${GTEST_DIR}/include -I${GTEST_DIR} -c $< -o $@

CLEAN_DIRS += ${BUILD_DIR}/obj

# Print out the generate Makefile snippet for debugging purposes
ifdef DEBUG_MAKEFILE
$(foreach target,${TARGETS},$(info $(call common_target,${target},release)))
$(foreach target,${TEST_TARGETS},$(info $(call test_target,${target})))
$(error Not building since DEBUG_MAKEFILE was specified)
endif

# Expand the build definitions for each provided target
$(foreach target,${TARGETS},$(eval $(call common_target,${target},release)))
$(foreach target,${TEST_TARGETS},$(eval $(call test_target,${target})))

# Build all non-test targets by default
all : ${TARGETS}

# Complete test suite, runs all possible test flavours)
full_test : valgrind_check coverage_check

clean :
	@rm -f $(sort ${CLEANS}) # make's sort function removes duplicates as a side effect
	@rm -fr $(sort ${CLEAN_DIRS})

# Makefile debugging target
#
# `make print-VARIABLE` will print the calculated value of `VARIABLE`
print-% :
	@echo $* = $($*)

-include ${DEPENDS}
