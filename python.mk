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

${PYTHON} ${ENV_DIR} ${PIP}:
	# Set up a fresh virtual environment and install pip
	virtualenv --setuptools --python=$(PYTHON_BIN) $(ENV_DIR)
	$(ENV_DIR)/bin/easy_install "setuptools==${SETUPTOOLS_VERSION}"

	# Ensure we have an up to date version of pip with wheel support
	${PIP} install --upgrade pip==9.0.1
	${PIP} install wheel==0.30.0

# Dummy targets onto which the targets defined in python_component below are
# added as dependencies.
${ENV_DIR}/.wheels-cleaned:
	touch $@

${ENV_DIR}/.wheels-built:
	touch $@

${ENV_DIR}/.wheels-installed:
	touch $@

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

# The wheelhouse can be overridden if desired
$1_WHEELHOUSE ?= $1_wheelhouse

${ENV_DIR}/.wheels-cleaned: ${ENV_DIR}/.$1-clean-wheels
${ENV_DIR}/.wheels-built: ${ENV_DIR}/.$1-build-wheels
${ENV_DIR}/.wheels-installed: ${ENV_DIR}/.$1-install-wheels

# Ensures that the wheelhouses are cleaned when source files change
${ENV_DIR}/.$1-clean-wheels: $${$1_SETUP} $${$1_SOURCES} ${PYTHON}
	# Remove the wheelhouse
	rm -rf $${$1_WHEELHOUSE}
	touch $$@

# Builds the wheels for this target
${ENV_DIR}/.$1-build-wheels: ${ENV_DIR}/.wheels-cleaned
	# For each setup.py file, generate the wheel
	$$(foreach setup, $${$1_SETUP}, \
		$${$1_FLAGS} ${PYTHON} $${setup} $$(if $${$1_BUILD_DIRS},build -b build_$$(subst .py,,$${setup})) bdist_wheel -d $${$1_WHEELHOUSE};)

	touch $$@

# Downloads required dependencies and installs them in the local environment
${ENV_DIR}/.$1-install-wheels: ${ENV_DIR}/.wheels-built $${$1_REQUIREMENTS}
	# Download the required dependencies
	$${$1_FLAGS} ${PIP} wheel -w $${$1_WHEELHOUSE} $$(foreach req,$${$1_REQUIREMENTS},-r $${req}) --find-links $${$1_WHEELHOUSE}

	# Install the required dependencies in the local environment
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
coverage: ${COVERAGE} ${ENV_DIR}/.test-requirements ${TEST_SETUP_PY}
	rm -rf htmlcov/
	${COVERAGE} erase
	# For each setup.py file in TEST_SETUP_PY, run under coverage
	$(foreach setup, ${TEST_SETUP_PY}, \
		$(if ${TEST_PYTHON_PATH},PYTHONPATH=${TEST_PYTHON_PATH},) ${COMPILER_FLAGS} ${COVERAGE} run $(if ${COVERAGE_SRC_DIR},--source ${COVERAGE_SRC_DIR},) $(if ${COVERAGE_EXCL},--omit "${COVERAGE_EXCL}",) -a ${setup} test;)
	${COVERAGE} combine
	${COVERAGE} report -m --fail-under 100
	${COVERAGE} html

.PHONY: test
test: ${ENV_DIR}/.test-requirements ${TEST_SETUP_PY}
	# Run test for each setup.py file in TEST_SETUP_PY
	$(foreach setup, ${TEST_SETUP_PY}, \
		$(if ${TEST_PYTHON_PATH},PYTHONPATH=${TEST_PYTHON_PATH},) ${COMPILER_FLAGS} ${PYTHON} ${setup} test -v;)

# Common test requirements.
# To use this, the following should be set:
#     * TEST_REQUIREMENTS: a list of the requirements files needed to install
#                          the test dependencies
${ENV_DIR}/.test-requirements: ${ENV_DIR}/.wheels-installed ${TEST_REQUIREMENTS}
	# Install the test requirements
	$(foreach reqs, ${TEST_REQUIREMENTS}, \
		${PIP} install -r ${reqs};)
	touch $@

${COVERAGE}: ${PIP}
	${PIP} install coverage==4.1

${FLAKE8}: ${ENV_DIR} ${PIP}
	${PIP} install flake8

.PHONY: verify
verify: ${FLAKE8}
	${FLAKE8} --select=E10,E11,E9,F "${FLAKE8_INCLUDE_DIR}" --exclude "${FLAKE8_EXCLUDE_DIR}"

.PHONY: style
style: ${FLAKE8}
	${FLAKE8} --select=E,W,C,N --max-line-length=100 "${FLAKE8_INCLUDE_DIR}"

${BANDIT}: ${ENV_DIR} ${PIP}
	${PIP} install bandit

.PHONY: analysis
analysis: ${BANDIT}
	# Scanning python code recursively for security issues using Bandit.
	# Files in -x are ignored and only high severity level (-lll) are shown.
	${ENV_DIR}/bin/bandit -r . -x "${BANDIT_EXCLUDE_LIST}" -lll

.PHONY: env
env: ${ENV_DIR}/.wheels-installed

.PHONY: clean
clean: envclean pyclean

.PHONY: envclean
envclean:
	rm -rf ${ROOT}/bin ${ROOT}/.eggs ${ROOT}/.wheelhouse ${ROOT}/*wheelhouse ${ROOT}/parts ${ROOT}/.installed.cfg ${ROOT}/bootstrap.py ${ROOT}/.downloads ${ROOT}/.buildout_downloads ${ROOT}/*.egg ${ROOT}/*.egg-info
	rm -rf ${ROOT}/distribute-*.tar.gz
	rm -rf $(ENV_DIR)

.PHONY: pyclean
pyclean:
	$(if ${CLEAN_SRC_DIR},find ${CLEAN_SRC_DIR} -name \*.pyc -exec rm -f {} \;,)
	$(if ${CLEAN_SRC_DIR},rm -rf ${CLEAN_SRC_DIR}/*.egg-info dist,)
	rm -rf ${ROOT}/build ${ROOT}/build_*
	rm -f ${ROOT}/.coverage
	rm -rf ${ROOT}/htmlcov/
