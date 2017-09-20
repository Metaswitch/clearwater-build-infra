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

.PHONY: analysis

# Common definitions
PYTHON := ${ENV_DIR}/bin/python
PIP := ${ENV_DIR}/bin/pip
FLAKE8 := ${ENV_DIR}/bin/flake8
BANDIT := ${ENV_DIR}/bin/bandit

${BANDIT}: ${ENV_DIR} ${PIP}
	${PIP} install bandit

analysis: ${BANDIT}
	# Scanning python code recursively for security issues using Bandit.
	# Files in -x are ignored and only high severity level (-lll) are shown.
	${ENV_DIR}/bin/bandit -r . -x "${BANDIT_EXCLUDE_LIST}" -lll

INSTALLER := ${PIP} install --compile \
                            --no-index \
                            --upgrade \
                            --pre \
                            --force-reinstall
