# Common packaging makefile
#
# Provides common setup for packages (both Debian and RPM).
#
# Copyright (C) Metaswitch Networks
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

ifeq ($(origin PKG_MINOR_VERSION), undefined)
# Need to use := here so that we evaluate it now, not each time we need it.
# (There's no "evaluate now, but only if it's not already defined" operator.)
PKG_MINOR_VERSION := $(shell date +%y%m%d.%H%M%S)
endif

# Package maintainer, and owner of the signing key.
CW_SIGNER ?= maintainers@projectclearwater.org
CW_SIGNER_REAL := Project Clearwater Maintainers

# thanks to http://stackoverflow.com/questions/1593051/how-to-programmatically-determine-the-current-checked-out-git-branch
GIT_BRANCH := $(shell branch=$$(git symbolic-ref -q HEAD); branch=$${branch\#\#refs/heads/}; branch=$${branch:-HEAD}; echo $$branch)

SHELL := bash
COPYRIGHT_FILE := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))COPYING
