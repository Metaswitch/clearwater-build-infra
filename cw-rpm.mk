# RPM package makefile
#
# Provides common logic for creating and pushing RPM packages.
#
# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

# Caller must set the following:
# PKG_COMPONENT or RPM_COMPONENT (RPM_COMPONENT takes precedence)
#                      - name of overall component for manifest
#                        (e.g., sprout)
# PKG_MAJOR_VERSION or RPM_MAJOR_VERSION (RPM_MAJOR_VERSION takes precedence)
#                      - major version number for package (e.g., 1.0)
# PKG_NAMES or RPM_NAMES (RPM_NAMES takes precedence)
#                      - space-separated base names of packages
#                        (e.g., sprout). For new projects this should not list
#                        the debug packages explicitly (the build
#                        infrastructure will spot them and install then and
#                        hanle appropriately).

# Caller may also set the following:
# PKG_MINOR_VERSION or RPM_MINOR_VERSION (RPM_MINOR_VERSION takes precedence)
#                      - minor version number for package (default is current timestamp)
# REPO_DIR             - path to repository to move packages to (default is unset,
#                        meaning don't move packages)
# REPO_SERVER          - username and server to scp pacakges to (default is unset,
#                        meaning move packages locally)
# CW_SIGNED            - whether to sign the generated package repository (default
#                        is unset, meaning don't sign; set to Y to sign).
#                        IMPORTANT: this signs the repo itself, which means that
#                        *all* packages in it are marked authentic, not just the
#                        ones we built just now.
# HARDENED_REPO_DIR    - path to the hardened repository to move packages to
#                        (default is unset, meaning don't move packages)
# HARDENED_REPO_SERVER - username and server for the hardened repository to scp
#                        packages to (default is unset, meaning move
#                        packages locally)

# Include common definitions
include build-infra/cw-pkg.mk

# Default RPM_* from PKG_*
RPM_COMPONENT ?= $(PKG_COMPONENT)
RPM_MAJOR_VERSION ?= $(PKG_MAJOR_VERSION)
RPM_MINOR_VERSION ?= $(PKG_MINOR_VERSION)

# Include the knowledge on how to move to the repo server
# Also sets RPM_NAMES and RPM_ARCH.
include build-infra/cw-rpm-move.mk

# Build and move to the repository server (if present).
.PHONY: rpm-only
rpm-only: rpm-build rpm-move rpm-move-hardened

# Build the .rpm files in rpm/RPMS.
.PHONY: rpm-build
rpm-build:
	# Clear out old RPMs
	rm -rf rpm/SRPMS/*
	rm -rf rpm/RPMS/*
ifneq ($(wildcard $(COPYRIGHT_FILE)),)
	# We have a COPYING file that contains the copyright information.
	# Extract the short name of the license and the URL for use in the RPM
	# copyright information.
	for line in $(shell cat $(COPYRIGHT_FILE)); do \
		if [[ $(line) == Copyright:* ]]; then \
			RPM_LICENSE=${line%%Copyright: *} \
		elif [[ $(line) == Source:* ]]; then \
			RPM_URL=${line%%Source: *} \
		fi \
	done
else
  echo "You must provide a COPYING file in the root of your repository in order to build packages."
  exit 1
endif
	# If this is built from a git@github.com: URL then output Git instructions for accessing the build tree
	echo "* $$(date -u +"%a %b %d %Y") $(CW_SIGNER_REAL) <$(CW_SIGNER)>" >rpm/changelog;\
	if [[ "$$(git config --get remote.origin.url)" =~ ^git@github.com: ]]; then\
	        echo "- built from $$(git config --get remote.origin.url|sed -e 's#^git@\([^:]*\):\([^/]*\)\([^.]*\)[.]git#https://\1/\2\3/tree/#')$$(git rev-parse HEAD)" >>rpm/changelog;\
		echo "  Use Git to access the source code for this build as follows:" >>rpm/changelog;\
		echo "    $$ git config --global url.\"https://github.com/\".insteadOf git@github.com:" >>rpm/changelog;\
		echo "    $$ git clone --recursive $$(git config --get remote.origin.url)" >>rpm/changelog;\
		echo "    Cloning into '$$(git config --get remote.origin.url|sed -e 's#^\([^:]*\):\([^/]*\)/\([^.]*\)[.]git#\3#')'..." >>rpm/changelog;\
		echo "      ..."  >>rpm/changelog;\
		echo "    $$ cd $$(git config --get remote.origin.url|sed -e 's#^\([^:]*\):\([^/]*\)/\([^.]*\)[.]git#\3#')" >>rpm/changelog;\
		echo "    $$ git checkout -q $$(git rev-parse HEAD)" >>rpm/changelog;\
		echo "    $$ git submodule update --init" >>rpm/changelog;\
		echo "      ..."  >>rpm/changelog;\
		echo "    $$"  >>rpm/changelog;\
	else\
		echo "- built from revision $$(git rev-parse HEAD)" >>rpm/changelog;\
	fi
	for pkg in ${RPM_NAMES} ; do\
		rpmbuild -ba rpm/$${pkg}.spec\
        	         --define "_topdir $(shell pwd)/rpm"\
        	         --define "rootdir $(shell pwd)"\
        	         --define "RPM_MAJOR_VERSION ${RPM_MAJOR_VERSION}"\
        	         --define "RPM_MINOR_VERSION ${RPM_MINOR_VERSION}"\
        	         --define "RPM_SIGNER ${CW_SIGNER}"\
					 --define "RPM_SIGNER_REAL ${CW_SIGNER_REAL}"
					 --define "RPM_LICENSE ${RPM_LICENSE}"
					 --define "RPM_URL ${RPM_URL}" || exit 1;\
	done
	if [ "$(CW_SIGNED)" = "Y" ] ; then \
		rpm --addsign --define "_gpg_name ${CW_SIGNER_REAL} <${CW_SIGNER}>" $$(ls rpm/RPMS/noarch/*.rpm 2>/dev/null || true) $$(ls rpm/RPMS/${RPM_ARCH}/*.rpm 2>/dev/null || true) ;\
	fi
