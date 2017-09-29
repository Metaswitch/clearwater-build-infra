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

INSTALLER := ${PIP} install --compile \
                            --no-index \
                            --upgrade \
                            --pre \
                            --force-reinstall

${PYTHON} ${ENV_DIR} ${PIP}:
	# Set up a fresh virtual environment and install pip
	virtualenv --setuptools --python=$(PYTHON_BIN) $(ENV_DIR)
	$(ENV_DIR)/bin/easy_install "setuptools==24"

	# Ensure we have an up to date version of pip with wheel support
	${PIP} install --upgrade pip==9.0.1
	${PIP} install wheel==0.30.0

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

${ENV_DIR}/.wheels-built: ${ENV_DIR}/.$1-build-wheels
${ENV_DIR}/.wheels-installed: ${ENV_DIR}/.$1-install-wheels

# Builds the wheels for this target
${ENV_DIR}/.$1-build-wheels: $${$1_SETUP} $${$1_SOURCES} ${PYTHON}
	# For each setup.py file, generate the wheel
	$$(foreach setup, $${$1_SETUP}, \
		$${$1_FLAGS} ${PYTHON} $${setup} build -b build_$$(subst .py,,$${setup}) bdist_wheel -d $${$1_WHEELHOUSE};)

	touch $$@

# Downloads required dependencies and installs them in the local environment
${ENV_DIR}/.$1-install-wheels: ${ENV_DIR}/.$1-build-wheels $${$1_REQUIREMENTS}
	# Download the required dependencies
	$${$1_FLAGS} ${PIP} wheel -w $${$1_WHEELHOUSE} $$(foreach req,$${$1_REQUIREMENTS},-r $${req}) --find-links $${$1_WHEELHOUSE}

	# Install the required dependencies in the local environment
	${INSTALLER} --find-links=$${$1_WHEELHOUSE} $${$1_WHEELS}  $$(foreach req,$${$1_REQUIREMENTS},-r $${req})

	touch $$@


endef

.PHONY: coverage
coverage: ${COVERAGE} ${ENV_DIR}/.wheels-installed
	rm -rf htmlcov/
	${COVERAGE} erase
	# For each setup.py file in COVERAGE_SETUP_PY, run under coverage
	$(foreach setup, ${COVERAGE_SETUP_PY}, \
		PYTHONPATH=${COVERAGE_PYTHON_PATH} ${COMPILER_FLAGS} ${COVERAGE} run $(if ${COVERAGE_SRC_DIR},--source ${COVERAGE_SRC_DIR},) $(if ${COVERAGE_EXCL},--omit "${COVERAGE_EXCL}",) -a ${setup} test;)
	${COVERAGE} combine
	${COVERAGE} report -m --fail-under 100
	${COVERAGE} xml

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

.PHONY: clean
clean: envclean pyclean

.PHONY: envclean
envclean:
	rm -rf bin .eggs .wheelhouse *_wheelhouse parts .installed.cfg bootstrap.py .downloads .buildout_downloads *.egg *.egg-info
	rm -rf distribute-*.tar.gz
	rm -rf $(ENV_DIR)

.PHONY: pyclean
pyclean:
	find ${SRC_DIR} -name \*.pyc -exec rm -f {} \;
	rm -rf ${SRC_DIR}/*.egg-info dist
	rm -rf build build_*
	rm -f .coverage
	rm -rf htmlcov/
