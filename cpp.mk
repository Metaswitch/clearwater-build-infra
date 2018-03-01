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
#   <target>_VALGRIND_EXCL - (optional) A Gtest filter to match on tests to be
#                            excluded from the valgrind check
#
# This Makefile snippet defines a few variables that may be useful when adding
# extra pre-requisites to targets:
#
#   CLEANS              - All files listed in this will be removed by `make clean`
#   CLEAN_DIRS          - All directories listed in this will be removed by `make clean`

.DEFAULT_GOAL := all
.PHONY : all test full_test valgrind valgrind_check coverage_check coverage_raw clean cppcheck

# Makefiles can override these if needed
ROOT ?= ..
GMOCK_DIR ?= ${ROOT}/modules/gmock
GTEST_DIR ?= ${GMOCK_DIR}/gtest
GCOVR_DIR ?= ${ROOT}/modules/gcovr
CPP_COMMON_DIR ?= ${ROOT}/modules/cpp-common
BUILD_DIR ?= ${ROOT}/build
SERVICE_TEST_DIR ?= ${ROOT}/service_tests

# Common rules to build any target
#
# @param $1 - Target name (final executable)
# @param $2 - Build flavor (valid values are `test` or `release`)
define common_target

# Calculate the object names for the $1 build
$1_OBJS := $$(patsubst %.cpp,$${BUILD_DIR}/$1/%.o,$${$1_SOURCES})
$1_DEPS := $$(patsubst %.cpp,$${BUILD_DIR}/$1/%.d,$${$1_SOURCES})
$1_CLANGTIDY := $$(patsubst %.cpp,$${BUILD_DIR}/$1/%.clangtidy,$${$1_SOURCES})

# Create alias for the object directory this allows the parent Makefile
# to add extra pre-requisites to specific objects (e.g. auto-generated
# header files)
$1_OBJECT_DIR := $${BUILD_DIR}/$1

# Object files are produced by compiling source files
$${$1_OBJS} : $${$1_OBJECT_DIR}/%.o : %.cpp
	@mkdir -p $${$1_OBJECT_DIR}
	${CXX} ${CXXFLAGS} ${CPPFLAGS} -MMD -MP $${$2_CPPFLAGS} $${$1_CPPFLAGS} $${$$<_CPPFLAGS} -c $$< -o $$@

# clang-tidy files are produced by analyzing source files
$${$1_CLANGTIDY} : $${$1_OBJECT_DIR}/%.clangtidy : %.cpp
	@mkdir -p $${$1_OBJECT_DIR}
	clang-tidy-3.8 -checks='*,-cppcoreguidelines-pro*,-modernize-use-auto,-modernize-use-nullptr,-llvm-include-order' $$< -- ${CXX} ${CXXFLAGS} ${CPPFLAGS} -MMD -MP $${$2_CPPFLAGS} $${$1_CPPFLAGS} > $$@


# Final linker step for $1
$${BUILD_DIR}/bin/$1 : $${$1_OBJS}
	@mkdir -p $${BUILD_DIR}/bin/
	${CXX} ${LDFLAGS} -o $$@ $$^ $${$2_LDFLAGS} $${$1_LDFLAGS}

# Shortcut alias to make $1
.PHONY : $1
$1 : $${BUILD_DIR}/bin/$1

# Include depends files from $1
DEPENDS += $${$1_DEPS}

# Clean up for $1
CLEANS += $${BUILD_DIR}/bin/$1
CLEAN_DIRS += $${$1_OBJECT_DIR}

.PHONY: clangtidy_$1
clangtidy_$1: $${$1_CLANGTIDY}
	cat $${$1_CLANGTIDY}

service_test:
ifeq ($2,release)
.PHONY: service_test_$1
service_test_$1: $${BUILD_DIR}/bin/$1
	if [ -d $${SERVICE_TEST_DIR} ]; then \
		cd $${SERVICE_TEST_DIR} && \
		bash -xe ./copy_files_to_docker_context.sh && \
		docker build -t $(shell whoami)-$$@ . && \
		docker run -t $(shell whoami)-$$@; \
		else \
		echo "No service tests found"; \
		fi

# Shortcut alias
.PHONY: service_test
service_test: service_test_$1
endif

CLEANS += $${$1_CLANGTIDY}

endef

# Extra rules for TEST_TARGETS
#
# @param $1 - Target name (final executable)
define test_target

# Call into standard build infrastructure for $1
$(call common_target,$1,test)

$${BUILD_DIR}/bin/$1 : $${BUILD_DIR}/obj/gmock-all.o $${BUILD_DIR}/obj/gtest-all.o

$1_LD_LIBRARY_PATH ?= ${ROOT}/usr/lib

.PHONY : run_$1
run_$1 : $${BUILD_DIR}/bin/$1
	rm -f $${BUILD_DIR}/$1/*.gcda
	LD_LIBRARY_PATH=$${$1_LD_LIBRARY_PATH} $$< ${EXTRA_TEST_ARGS}

# This sentinel file proves the tests have *all* been run on this build (mostly for coverage)
$${BUILD_DIR}/$1/.$1_already_run : $${BUILD_DIR}/bin/$1
	rm -f $${BUILD_DIR}/$1/*.gcda
	LD_LIBRARY_PATH=$${$1_LD_LIBRARY_PATH} $$< --gtest_output=xml:$${BUILD_DIR}/$1/gtest_output.xml
	@touch $$@

.PHONY : debug_$1
debug_$1 : $${BUILD_DIR}/bin/$1
	LD_LIBRARY_PATH=$${$1_LD_LIBRARY_PATH} gdb --args $$< $${EXTRA_TEST_ARGS}

# Valgrind arguments for $1
$1_VALGRIND_ARGS += --gen-suppressions=all --leak-check=full --track-origins=yes --malloc-fill=cc --free-fill=df

.PHONY : valgrind_check_$1
valgrind_check_$1 : $${BUILD_DIR}/bin/$1
	LD_LIBRARY_PATH=$${$1_LD_LIBRARY_PATH} valgrind $${$1_VALGRIND_ARGS} --xml=yes --xml-file=$${BUILD_DIR}/$1/valgrind_output.xml $$< $$(if $${$1_VALGRIND_EXCL},--gtest_filter="-*DeathTest*:$${$1_VALGRIND_EXCL}",--gtest_filter="-*DeathTest*") ${EXTRA_TEST_ARGS}
	@mkdir -p $${BUILD_DIR}/scratch/
	@xmllint --xpath '//error/kind' $${BUILD_DIR}/$1/valgrind_output.xml 2>&1 | \
		sed -e 's#<kind>##g' | \
		sed -e 's#</kind>#\n#g' | \
		sort > $${BUILD_DIR}/scratch/valgrind.tmp
	@if grep -q -v "XPath set is empty" $${BUILD_DIR}/scratch/valgrind.tmp ; then \
		echo "Error: some memory errors have been detected" ; \
		cat $${BUILD_DIR}/scratch/valgrind.tmp ; \
		echo "See $${BUILD_DIR}/$1/valgrind_output.xml for further details." ; \
		exit 2 ; \
	fi

CLEANS += $${BUILD_DIR}/scratch/valgrind.tmp

.PHONY : valgrind_$1
valgrind_$1 : $${BUILD_DIR}/bin/$1
	LD_LIBRARY_PATH=$${$1_LD_LIBRARY_PATH} valgrind $${$1_VALGRIND_ARGS} $$< $${EXTRA_TEST_ARGS}

# Coverage arguments for $1
COMMON_COVERAGE_EXCLUSIONS := ^ut/|^$${GMOCK_DIR}
ifdef $1_COVERAGE_EXCLUSIONS
	COVERAGE_EXCLUSIONS := $${COMMON_COVERAGE_EXCLUSIONS}|$${$1_COVERAGE_EXCLUSIONS}
else
	COVERAGE_EXCLUSIONS := $${COMMON_COVERAGE_EXCLUSIONS}
endif

# Default coverage root - makefiles can override this if necessary
COVERAGE_ROOT ?= $(shell pwd)
$1_COVERAGE_ARGS := --root=$${COVERAGE_ROOT} --object-directory=$(shell pwd) --exclude="$${COVERAGE_EXCLUSIONS}" $${$1_OBJECT_DIR}

$1_EXCLUSION_FILE ?= ut/coverage-not-yet

$${BUILD_DIR}/$1/coverage.xml : $${BUILD_DIR}/$1/.$1_already_run
	@${GCOVR_DIR}/scripts/gcovr $${$1_COVERAGE_ARGS} --xml > $$@ || (rm $$@; exit 2)

.PHONY : coverage_check_$1
coverage_check_$1 : $${BUILD_DIR}/$1/coverage.xml
	@mkdir -p $${BUILD_DIR}/scratch/
	@xmllint --xpath '//class[count(lines/line) > 0 and @line-rate != "1.0"]/@filename' $$< \
		| tr ' ' '\n' \
		| grep filename= \
		| cut -d\" -f2 \
		| sort > $${BUILD_DIR}/scratch/coverage_$1.tmp
	@sort $${$1_EXCLUSION_FILE} | comm -23 $${BUILD_DIR}/scratch/coverage_$1.tmp - > $${BUILD_DIR}/scratch/coverage_$1_filtered.tmp
	@if grep -q ^ $${BUILD_DIR}/scratch/coverage_$1_filtered.tmp ; then \
		echo "Error: some files unexpectedly have less than 100% code coverage:" ; \
		cat $${BUILD_DIR}/scratch/coverage_$1_filtered.tmp ; \
		exit 2 ; \
	fi
CLEANS += $${BUILD_DIR}/scratch/coverage_$1.tmp $${BUILD_DIR}/scratch/coverage_$1_filtered.tmp

.PHONY : coverage_raw_$1
coverage_raw_$1 : $${BUILD_DIR}/$1/.$1_already_run
	@${GCOVR_DIR}/scripts/gcovr $${$1_COVERAGE_ARGS} --sort-percentage

.PHONY : cppcheck_$1
cppcheck_$1 :
	cppcheck --enable=all --quiet -i ut -I ../include -I ../modules/cpp-common/include .

test : run_$1
valgrind : valgrind_$1
valgrind_check : valgrind_check_$1
coverage_check : coverage_check_$1
coverage_raw : coverage_raw_$1
clangtidy: clangtidy_$1
cppcheck : cppcheck_$1

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
  EXTRA_TEST_ARGS ?= --gtest_filter=$(JUSTTEST)
endif

${BUILD_DIR}/obj/gmock-all.o : ${GMOCK_DIR}/src/gmock-all.cc ${GMOCK_DIR}/include/gmock/*.h ${GMOCK_DIR}/include/gmock/internal/*.h
	@mkdir -p ${BUILD_DIR}/obj
	${CXX} ${test_CPPFLAGS} -I${GTEST_DIR}/include -I${GMOCK_DIR}/include -I${GMOCK_DIR} -c $< -o $@
${BUILD_DIR}/obj/gtest-all.o : ${GTEST_DIR}/src/gtest-all.cc ${GTEST_DIR}/include/gtest/*.h ${GTEST_DIR}/include/gtest/internal/*.h
	@mkdir -p ${BUILD_DIR}/obj
	${CXX} ${test_CPPFLAGS} -I${GTEST_DIR}/include -I${GTEST_DIR}/include -I${GTEST_DIR} -c $< -o $@

CLEAN_DIRS += ${BUILD_DIR}/obj

# In case there are no test/non-test targets for this project
TARGETS ?=
TEST_TARGETS ?=

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
# Includes coverage_raw so we get the formatted coverage output
full_test : valgrind_check service_test coverage_raw coverage_check

clean :
	@rm -f $(sort ${CLEANS}) # make's sort function removes duplicates as a side effect
	@rm -fr $(sort ${CLEAN_DIRS})

# Makefile debugging target
#
# `make print-VARIABLE` will print the calculated value of `VARIABLE`
print-% :
	@echo $* = $($*)

-include ${DEPENDS}
