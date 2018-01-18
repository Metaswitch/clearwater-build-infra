# Python makefile
#
# Provides common logic for Python code in Debian packages.
#
# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.


# Common definitions
PYTHON := ${ENV_DIR}/bin/python
PIP := ${ENV_DIR}/bin/pip
FLAKE8 := ${ENV_DIR}/bin/flake8
COVERAGE := ${ENV_DIR}/bin/coverage
BANDIT := ${ENV_DIR}/bin/bandit

# If not set, default TEST_SETUP_PY
TEST_SETUP_PY ?= setup.py

INSTALLER := ${PIP} install --compile \
                            --no-index \
                            --upgrade \
                            --pre \
                            --force-reinstall

SETUPTOOLS_VERSION ?= 24
PIP_VERSION ?= 9.0.1
WHEEL_VERSION ?= 0.30.0

${ENV_DIR}/.pip_${PIP_VERSION}_wheel_${WHEEL_VERSION}:
	# Delete any existing venv
	rm -rf ${ENV_DIR}

	# Set up a fresh virtual environment and install pip
	virtualenv --setuptools --python=$(PYTHON_BIN) $(ENV_DIR)
	$(ENV_DIR)/bin/easy_install "setuptools==${SETUPTOOLS_VERSION}"

	# Ensure we have an up to date version of pip with wheel support
	${PIP} install --upgrade pip==${PIP_VERSION}
	${PIP} install wheel==${WHEEL_VERSION}

	touch $@

# This target builds all required wheelhouses and is therefore expected to be a
# dependency of `make deb`
.PHONY: wheelhouses

# A dummy test target, to which dependencies are added for each test component
.PHONY: test

# Common coverage target.
#
# COVERAGE_SETUP_PY is a list of setup.py files to be run under coverage, and is
# built up by adding the <target>_TEST_SETUP for each python_test_component.
#
# Optional parameters:
#  - COVERAGE_SRC_DIR is the directory in which we run coverage.
#  - COVERAGE_EXCL are files to be excluded from coverage
#  - TEST_PYTHON_PATH is the python path to use
#  - COMPILER_FLAGS are any additional flags to  be used.
.PHONY: coverage
coverage: ${COVERAGE} ${ENV_DIR}/.test-requirements
	rm -rf htmlcov/
	${COVERAGE} erase
	# For each setup.py file in TEST_SETUP_PY, run under coverage
	$(foreach setup, ${COVERAGE_SETUP_PY}, \
		$(if ${TEST_PYTHON_PATH},PYTHONPATH=${TEST_PYTHON_PATH},) ${COMPILER_FLAGS} \
			${COVERAGE} run $(if ${COVERAGE_SRC_DIR},--source ${COVERAGE_SRC_DIR},) \
			$(if ${COVERAGE_EXCL},--omit "${COVERAGE_EXCL}",) -a ${setup} test &&) true
	${COVERAGE} combine
	${COVERAGE} report -m --fail-under 100
	${COVERAGE} html

# Dummy test requirements target to which we add the requirements for each component,
# so that coverage can depend on this target.
${ENV_DIR}/.test-requirements:
	touch $@

# Common rules for a python component that includes tests
# @param $1 - (Required) Target name
# @param $2 - (Optional) If set to "EXCLUDE_TEST", the component will not be
#             added to the `test` target or the coverage target
#
# e.g. you might have an fv_test target, which you don't want to be added to
# coverage or the `test` target, which you'd do with:
#     $(eval $(call python_test_component,fv,EXCLUDE_TEST))
#
# Each target must supply:
#   - <target>_TEST_REQUIREMENTS - A list of the requirements files that the target uses
#   - <target>_TEST_SETUP        - The setup.py file used to run the tests
define python_test_component

# If required, add this test setup file to the list of setup files to be run
# under coverage, and add this _test target to the common `test` target
ifneq ($2, EXCLUDE_TEST)
COVERAGE_SETUP_PY += $${$1_TEST_SETUP}
test: $1_test
endif

# Whenever the test requirements change, we must delete our venv as we may have
# the wrong requirements installed
${ENV_DIR}/.pip_${PIP_VERSION}_wheel_${WHEEL_VERSION}: $${$1_TEST_REQUIREMENTS}

${ENV_DIR}/.$1-test-requirements: $${$1_TEST_REQUIREMENTS} ${ENV_DIR}/.pip_${PIP_VERSION}_wheel_${WHEEL_VERSION}
	# Install the test requirements for this component
	$$(foreach reqs, $${$1_TEST_REQUIREMENTS}, ${PIP} install -r $${reqs} &&) true
	touch $$@

.PHONY: $1_test
$1_test: ${ENV_DIR}/.$1-test-requirements
	$(if ${TEST_PYTHON_PATH},PYTHONPATH=${TEST_PYTHON_PATH},) ${COMPILER_FLAGS} ${PYTHON} $${$1_TEST_SETUP} test -v

${ENV_DIR}/.test-requirements: ${ENV_DIR}/.$1-test-requirements

endef

# Common rules to build a python component. Includes adding a test target.
#
# @param $1 - Target name
#
# Each target must supply:
#   - <target>_SETUP        - A list of the setup.py files that the target depends on
#   - <target>_REQUIREMENTS - A list of the requirements files that the target uses
#   - <target>_SOURCES      - A list of the python source files that go into the wheel
#   - <target>_WHEELS       - (Optional) A list of built wheels that should be installed in the environent.
#   - <target>_FLAGS        - (Optional) Extra flags to be passed to python commands
#   - <target>_BUILD_DIRS   - (Optional) If specified, this component uses a the build directory {ROOT}/build_<target>
#
# The location of the wheelhouse can be overridden if desired, by specifying
# <target>_WHEELHOUSE
define python_component

# Create common tests targets for this component
$(call python_test_component,$1)

# The wheelhouse can be overridden if desired
$1_WHEELHOUSE ?= $1_wheelhouse

# Whenever the requirements change, we must delete our venv as we may have the
# wrong requirements installed
${ENV_DIR}/.pip_${PIP_VERSION}_wheel_${WHEEL_VERSION}: $${$1_REQUIREMENTS}

# To create the wheelhouse, we need to download external wheels and build our own wheels
$${$1_WHEELHOUSE}/.wheelhouse_complete: $${$1_WHEELHOUSE}/.download-wheels $${$1_WHEELHOUSE}/.build-wheels
	touch $$@

# Add this wheelhouse to the wheelhouses target
wheelhouses: $${$1_WHEELHOUSE}/.wheelhouse_complete

$${$1_WHEELHOUSE}/.clean-wheels: $${$1_REQUIREMENTS} ${ENV_DIR}/.pip_${PIP_VERSION}_wheel_${WHEEL_VERSION}
	# Whenever the requirements change, clear out the wheelhouse
	rm -rf $${$1_WHEELHOUSE}/*
	mkdir -p $${$1_WHEELHOUSE}
	touch $$@

$${$1_WHEELHOUSE}/.download-wheels: $${$1_WHEELHOUSE}/.clean-wheels
	# Download the required dependencies for this component
	$${$1_FLAGS} ${PIP} wheel -w $${$1_WHEELHOUSE} $$(foreach req,$${$1_REQUIREMENTS},-r $${req}) --find-links $${$1_WHEELHOUSE}
	touch $$@

# Builds the wheels for this component
$${$1_WHEELHOUSE}/.build-wheels: $${$1_SETUP} $${$1_SOURCES} $${$1_WHEELHOUSE}/.clean-wheels
	# For each setup.py file, generate the wheel
	$$(foreach setup, $${$1_SETUP}, \
		$${$1_FLAGS} ${PYTHON} $${setup} \
			$$(if $${$1_BUILD_DIRS},build -b ${ROOT}/build_$$(subst .py,,$${setup})) \
			bdist_wheel -d $${$1_WHEELHOUSE} &&) true
	touch $$@

${ENV_DIR}/.$1-install-wheels: $${$1_WHEELHOUSE}/.download-wheels
	# Install all wheels in the wheelhouse into the virtual env for this component
	${INSTALLER} --find-links=$${$1_WHEELHOUSE} \
		$$(if $${$1_EXTRA_LINKS},--find-links=$${$1_EXTRA_LINKS},) \
		$$(foreach req,$${$1_REQUIREMENTS},-r $${req})
	touch $$@

${ENV_DIR}/.$1-install-built-wheels: $${$1_WHEELHOUSE}/.download-wheels $${$1_WHEELHOUSE}/.build-wheels
	# Install all wheels in the wheelhouse into the virtual env for this component
	${INSTALLER} --find-links=$${$1_WHEELHOUSE} $$(if $${$1_EXTRA_LINKS},--find-links=$${$1_EXTRA_LINKS},) $${$1_WHEELS}
	touch $$@

# To run the tests, we need to install the dependencies
${ENV_DIR}/.$1-test-requirements: ${ENV_DIR}/.$1-install-wheels ${ENV_DIR}/.$1-install-built-wheels

endef

${COVERAGE}: ${ENV_DIR}/.pip_${PIP_VERSION}_wheel_${WHEEL_VERSION}
	${PIP} install coverage==4.1

${FLAKE8}: ${ENV_DIR}/.pip_${PIP_VERSION}_wheel_${WHEEL_VERSION}
	${PIP} install flake8

.PHONY: verify
verify: ${FLAKE8}
	${FLAKE8} --select=E10,E11,E9,F "${FLAKE8_INCLUDE_DIR}" --exclude "${FLAKE8_EXCLUDE_DIR}"

.PHONY: style
style: ${FLAKE8}
	${FLAKE8} --select=E,W,C,N --max-line-length=100 "${FLAKE8_INCLUDE_DIR}"

.PHONY: full_test
full_test: test coverage verify analysis

${BANDIT}: ${ENV_DIR}/.pip_${PIP_VERSION}_wheel_${WHEEL_VERSION}
	${PIP} install bandit

.PHONY: analysis
analysis: ${BANDIT}
	# Scanning python code recursively for security issues using Bandit.
	# Files in -x are ignored. Only issues of medium severity and above (-ll) are shown.
	${ENV_DIR}/bin/bandit -r . -x "${BANDIT_EXCLUDE_LIST}" -ll

.PHONY: env
env: ${ENV_DIR}/.pip_${PIP_VERSION}_wheel_${WHEEL_VERSION}

.PHONY: clean
clean: envclean pyclean

.PHONY: envclean
envclean:
	rm -rf ${ROOT}/bin ${ROOT}/.eggs ${ROOT}/.wheelhouse ${ROOT}/*wheelhouse ${ROOT}/parts ${ROOT}/.installed.cfg ${ROOT}/bootstrap.py ${ROOT}/.downloads ${ROOT}/.buildout_downloads ${ROOT}/*.egg ${ROOT}/*.egg-info
	rm -rf $(ENV_DIR)

.PHONY: pyclean
pyclean:
	$(if ${CLEAN_SRC_DIR},find ${CLEAN_SRC_DIR} -name \*.pyc -exec rm -f {} \;,)
	$(if ${CLEAN_SRC_DIR},rm -rf ${CLEAN_SRC_DIR}/*.egg-info dist,)
	rm -rf ${ROOT}/build ${ROOT}/build_*
	rm -f ${ROOT}/.coverage
	rm -rf ${ROOT}/htmlcov/
