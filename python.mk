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

${ENV_DIR}/.env:
	# Delete any existing venv
	rm -rf ${ENV_DIR}

	# Set up a fresh virtual environment and install pip
	virtualenv --setuptools --python=$(PYTHON_BIN) $(ENV_DIR)
	$(ENV_DIR)/bin/easy_install "setuptools==${SETUPTOOLS_VERSION}"

	# Ensure we have an up to date version of pip with wheel support
	${PIP} install --upgrade pip==9.0.1
	${PIP} install wheel==0.30.0

	touch $@

# Dummy targets onto which the targets defined in python_component below are
# added as dependencies.
${ENV_DIR}/.download-external-wheels:
	touch $@

${ENV_DIR}/.install-external-wheels:
	touch $@

${ENV_DIR}/.build-wheels:
	touch $@

# This target builds all required wheelhouses (and is therefore normally a dependency of `make deb`)
.PHONY: wheelhouses
wheelhouses: ${ENV_DIR}/.download-external-wheels

# Common rules for a python component that includes tests
# @param $1 - Target name
#
# Each target must supply:
#   - <target>_TEST_REQUIREMENTS - A list of the requirements files that the target uses
#   - <target>_TEST_SETUP        - The setup.py file used to run the tests
#
define python_test_component

${ENV_DIR}/.$1-test-requirements: $${$1_TEST_REQUIREMENTS} ${ENV_DIR}/.env
	# Install the test requirements for this component
	$$(foreach reqs, $${$1_TEST_REQUIREMENTS}, ${PIP} install -r $${reqs} &&) true
	touch $$@

.PHONY: $1_test
$1_test: ${ENV_DIR}/.$1-test-requirements
	$(if ${TEST_PYTHON_PATH},PYTHONPATH=${TEST_PYTHON_PATH},) ${COMPILER_FLAGS} ${PYTHON} $${$1_TEST_SETUP} test -v

${ENV_DIR}/.test-requirements: ${ENV_DIR}/.$1-test-requirements

test: $1_test
endef

# Common rules to build a python component
#
# @param $1 - Target name
#
# Each target must supply:
#   - <target>_SETUP        - A list of the setup.py files that the target depends on
#   - <target>_REQUIREMENTS - A list of the requirements files that the target uses
#   - <target>_SOURCES      - A list of the python source files that go into the wheel
#   - <target>_WHEELS       - A list of the wheels that are produced
#   - <target>_FLAGS        - (Optional) Extra flags to be passed to python commands
#
# The location of the wheelhouse can be overridden if desired, by specifying
# <target>_WHEELHOUSE
define python_component

# Create common tests targets for this component
$(call python_test_component,$1)

# The wheelhouse can be overridden if desired
$1_WHEELHOUSE ?= $1_wheelhouse

${ENV_DIR}/.download-external-wheels: $${$1_WHEELHOUSE}/.$1-download-wheels
${ENV_DIR}/.install-external-wheels: ${ENV_DIR}/.$1-install-wheels
${ENV_DIR}/.build-wheels: $${$1_WHEELHOUSE}/.$1-build-wheels

# Whenever the requirements change, we must delete our venv as we may have the
# wrong requirements installed
${ENV_DIR}/.env: $${$1_REQUIREMENTS}

# To create the wheelhouse, we need to download external wheels and build our own wheels
$${$1_WHEELHOUSE}/.wheelhouse_complete: $${$1_WHEELHOUSE}/.$1-download-wheels $${$1_WHEELHOUSE}/.$1-build-wheels
	touch $$@

# Add this wheelhouse to the wheelhouses target
wheelhouses: $${$1_WHEELHOUSE}/.wheelhouse_complete

$${$1_WHEELHOUSE}/.clean-wheels: $${$1_REQUIREMENTS} ${ENV_DIR}/.env
	# Whenever the requirements change, clear out the wheelhouse
	rm -rf $${$1_WHEELHOUSE}/*
	mkdir -p $${$1_WHEELHOUSE}
	touch $$@

$${$1_WHEELHOUSE}/.$1-download-wheels: $${$1_WHEELHOUSE}/.clean-wheels
  # Download the required dependencies for this component
	$${$1_FLAGS} ${PIP} wheel -w $${$1_WHEELHOUSE} $$(foreach req,$${$1_REQUIREMENTS},-r $${req}) --find-links $${$1_WHEELHOUSE}
	touch $$@

# Builds the wheels for this component
$${$1_WHEELHOUSE}/.$1-build-wheels: $${$1_SETUP} $${$1_SOURCES} $${$1_WHEELHOUSE}/.clean-wheels
	# For each setup.py file, generate the wheel
	$$(foreach setup, $${$1_SETUP}, \
		$${$1_FLAGS} ${PYTHON} $${setup} $$(if $${$1_BUILD_DIRS},build -b ${ROOT}/build_$$(subst .py,,$${setup})) bdist_wheel -d $${$1_WHEELHOUSE} &&) true
	touch $$@

${ENV_DIR}/.$1-install-wheels: $${$1_WHEELHOUSE}/.$1-download-wheels
  # Install all wheels in the wheelhouse into the virtual env for this component
	${INSTALLER} --find-links=$${$1_WHEELHOUSE} $$(if $${$1_EXTRA_LINKS},--find-links=$${$1_EXTRA_LINKS},) $${$1_WHEELS} $$(foreach req,$${$1_REQUIREMENTS},-r $${req})
	touch $$@

endef


# Common test and coverage targets.
# To use these, the following must be defined:
#     * TEST_SETUP_PY: list of the setup.py files that are run under coverage
#
# The following are optional, but will be used if defined:
#     * TEST_PYTHON_PATH: the PYTHONPATH used for the tests
#     * COMPILER_FLAGS: compiler flags to be used
#     * COVERAGE_SRC_DIR: the source directory for the coverage run
#     * COVERAGE_EXCL: excluded files
#
.PHONY: coverage
coverage: ${COVERAGE} ${ENV_DIR}/.test-requirements ${ENV_DIR}/.install-external-wheels ${COVERAGE_SETUP_PY}
	rm -rf htmlcov/
	${COVERAGE} erase
	# For each setup.py file in TEST_SETUP_PY, run under coverage
	$(foreach setup, ${COVERAGE_SETUP_PY}, \
		$(if ${TEST_PYTHON_PATH},PYTHONPATH=${TEST_PYTHON_PATH},) ${COMPILER_FLAGS} ${COVERAGE} run $(if ${COVERAGE_SRC_DIR},--source ${COVERAGE_SRC_DIR},) $(if ${COVERAGE_EXCL},--omit "${COVERAGE_EXCL}",) -a ${setup} test &&) true
	${COVERAGE} combine
	${COVERAGE} report -m --fail-under 100
	${COVERAGE} html

${ENV_DIR}/.test-requirements:
	touch $@

.PHONY: test

${COVERAGE}: ${ENV_DIR}/.env
	${PIP} install coverage==4.1

${FLAKE8}: ${ENV_DIR}/.env
	${PIP} install flake8

.PHONY: verify
verify: ${FLAKE8}
	${FLAKE8} --select=E10,E11,E9,F "${FLAKE8_INCLUDE_DIR}" --exclude "${FLAKE8_EXCLUDE_DIR}"

.PHONY: style
style: ${FLAKE8}
	${FLAKE8} --select=E,W,C,N --max-line-length=100 "${FLAKE8_INCLUDE_DIR}"

${BANDIT}: ${ENV_DIR}/.env
	${PIP} install bandit

.PHONY: analysis
analysis: ${BANDIT}
	# Scanning python code recursively for security issues using Bandit.
	# Files in -x are ignored and only high severity level (-lll) are shown.
	${ENV_DIR}/bin/bandit -r . -x "${BANDIT_EXCLUDE_LIST}" -lll

.PHONY: env
env: ${ENV_DIR}/.env

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
