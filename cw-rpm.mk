# RPM package makefile
#
# Provides common logic for creating and pushing RPM packages.
#
# Project Clearwater - IMS in the Cloud
# Copyright (C) 2016  Metaswitch Networks Ltd
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version, along with the "Special Exception" for use of
# the program along with SSL, set forth below. This program is distributed
# in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details. You should have received a copy of the GNU General Public
# License along with this program.  If not, see
# <http://www.gnu.org/licenses/>.
#
# The author can be reached by email at clearwater@metaswitch.com or by
# post at Metaswitch Networks Ltd, 100 Church St, Enfield EN2 6BQ, UK
#
# Special Exception
# Metaswitch Networks Ltd  grants you permission to copy, modify,
# propagate, and distribute a work formed by combining OpenSSL with The
# Software, or a work derivative of such a combination, even if such
# copying, modification, propagation, or distribution would otherwise
# violate the terms of the GPL. You must comply with the GPL in all
# respects for all of the code used other than OpenSSL.
# "OpenSSL" means OpenSSL toolkit software distributed by the OpenSSL
# Project and licensed under the OpenSSL Licenses, or a work based on such
# software and licensed under the OpenSSL Licenses.
# "OpenSSL Licenses" means the OpenSSL License and Original SSLeay License
# under which the OpenSSL Project distributes the OpenSSL toolkit software,
# as those licenses appear in the file LICENSE-OPENSSL.

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
RPM_NAMES ?= $(PKG_NAMES)

RPM_ARCH := $(shell rpmbuild -E %{_arch} 2>/dev/null)

# Commands to build an RPM package repo.
RPM_BUILD_REPO := createrepo .
ifeq ($(CW_SIGNED), Y)
RPM_BUILD_REPO := $(RPM_BUILD_REPO) ; \
                  gpg -abs -u $(CW_SIGNER) repodata/repomd.xml
endif

# Build and move to the repository server (if present).
.PHONY: rpm-only
rpm-only: rpm-build rpm-move rpm-move-hardened

# Build the .rpm files in rpm/RPMS.
.PHONY: rpm-build
rpm-build:
	# Clear out old RPMs
	rm -rf rpm/SRPMS/*
	rm -rf rpm/RPMS/*
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
        	         --define "RPM_SIGNER_REAL ${CW_SIGNER_REAL}" || exit 1;\
	done
	if [ "$(CW_SIGNED)" = "Y" ] ; then \
		rpm --addsign --define "_gpg_name ${CW_SIGNER_REAL} <${CW_SIGNER}>" $$(ls rpm/RPMS/noarch/*.rpm 2>/dev/null || true) $$(ls rpm/RPMS/${RPM_ARCH}/*.rpm 2>/dev/null || true) ;\
	fi

# Move to repository.  If REPO_SERVER is specified, known_hosts on this
# server must include $REPO_SERVER's server key, and authorized_keys on
# $REPO_SERVER must include this server's user key.  ssh-copy-id can be
# used to achieve this.
.PHONY: rpm-move
rpm-move:
	@if [ "${REPO_DIR}" != "" ] ; then                                                                                    \
	  if [ "${REPO_SERVER}" != "" ] ; then                                                                                \
	    echo Copying to directory ${REPO_DIR} on repo server ${REPO_SERVER}... ;                                          \
	    ssh ${REPO_SERVER} mkdir -p '${REPO_DIR}/noarch/RPMS' '${REPO_DIR}/${RPM_ARCH}/RPMS' ;                            \
	    if [ -n "${REPO_DELETE_OLD}" ] ; then                                                                             \
	      ssh ${REPO_SERVER} rm -f $(patsubst %, '${REPO_DIR}/noarch/RPMS/%-*', ${RPM_NAMES})                             \
	                               $(patsubst %, '${REPO_DIR}/noarch/RPMS/%-debuginfo-*', ${RPM_NAMES})                   \
	                               $(patsubst %, '${REPO_DIR}/${RPM_ARCH}/RPMS/%-*', ${RPM_NAMES})                        \
	                               $(patsubst %, '${REPO_DIR}/${RPM_ARCH}/RPMS/%-debuginfo-*', ${RPM_NAMES}) ;            \
	    fi ;                                                                                                              \
	    if ls -A rpm/RPMS/noarch/*.rpm > /dev/null ; then                                                                 \
	      scp rpm/RPMS/noarch/*.rpm ${REPO_SERVER}:${REPO_DIR}/noarch/RPMS/ ;                                             \
	    fi ;                                                                                                              \
	    if ls -A rpm/RPMS/${RPM_ARCH}/*.rpm > /dev/null ; then                                                            \
	      scp rpm/RPMS/${RPM_ARCH}/*.rpm ${REPO_SERVER}:${REPO_DIR}/${RPM_ARCH}/RPMS/ ;                                   \
	    fi ;                                                                                                              \
	    ssh ${REPO_SERVER} 'cd ${REPO_DIR} ; ${RPM_BUILD_REPO}' ;                                                         \
	  else                                                                                                                \
	    mkdir -p ${REPO_DIR}/noarch/RPMS ${REPO_DIR}/${RPM_ARCH}/RPMS ;                                                   \
	    if [ -n "${REPO_DELETE_OLD}" ] ; then                                                                             \
	      rm -f $(patsubst %, ${REPO_DIR}/noarch/RPMS/%-*, ${RPM_NAMES})                                                  \
	            $(patsubst %, ${REPO_DIR}/noarch/RPMS/%-debuginfo-*, ${RPM_NAMES})                                        \
	            $(patsubst %, ${REPO_DIR}/${RPM_ARCH}/RPMS/%-*, ${RPM_NAMES})                                             \
	            $(patsubst %, ${REPO_DIR}/${RPM_ARCH}/RPMS/%-debuginfo-*, ${RPM_NAMES}) ;                                 \
	    fi ;                                                                                                              \
	    if ls -A rpm/RPMS/noarch/*.rpm > /dev/null 2>&1 ; then                                                            \
	      mv rpm/RPMS/noarch/*.rpm ${REPO_DIR}/noarch/RPMS/ ;                                                             \
	    fi ;                                                                                                              \
	    if ls -A rpm/RPMS/${RPM_ARCH}/*.rpm > /dev/null 2>&1 ; then                                                       \
	      mv rpm/RPMS/${RPM_ARCH}/*.rpm ${REPO_DIR}/${RPM_ARCH}/RPMS/ ;                                                   \
	    fi ;                                                                                                              \
	    cd ${REPO_DIR} ; ${RPM_BUILD_REPO}; cd - >/dev/null ;                                                             \
	  fi                                                                                                                  \
	fi

.PHONY: rpm-move-hardened
rpm-move-hardened:
	@if [ "${HARDENED_REPO_DIR}" != "" ] ; then                                                                           \
	  if [ "${HARDENED_REPO_SERVER}" != "" ] ; then                                                                       \
	    echo Copying to directory ${HARDENED_REPO_DIR} on repo server ${HARDENED_REPO_SERVER}... ;                        \
	    ssh ${HARDENED_REPO_SERVER} mkdir -p '${HARDENED_REPO_DIR}/noarch/RPMS' '${HARDENED_REPO_DIR}/${RPM_ARCH}/RPMS' ; \
	    if [ -n "${REPO_DELETE_OLD}" ] ; then                                                                             \
	      ssh ${HARDENED_REPO_SERVER} rm -f $(patsubst %, '${HARDENED_REPO_DIR}/noarch/RPMS/%-*', ${RPM_NAMES})           \
	                                        $(patsubst %, '${HARDENED_REPO_DIR}/noarch/RPMS/%-debuginfo-*', ${RPM_NAMES}) \
	                                        $(patsubst %, '${HARDENED_REPO_DIR}/${RPM_ARCH}/RPMS/%-*', ${RPM_NAMES})      \
	                                        $(patsubst %, '${HARDENED_REPO_DIR}/${RPM_ARCH}/RPMS/%-debuginfo-*', ${RPM_NAMES}) ; \
	    fi ;                                                                                                              \
	    if ls -A rpm/RPMS/noarch/*.rpm > /dev/null ; then                                                                 \
	      scp rpm/RPMS/noarch/*.rpm ${HARDENED_REPO_SERVER}:${HARDENED_REPO_DIR}/noarch/RPMS/ ;                           \
	    fi ;                                                                                                              \
	    if ls -A rpm/RPMS/${RPM_ARCH}/*.rpm > /dev/null ; then                                                            \
	      scp rpm/RPMS/${RPM_ARCH}/*.rpm ${HARDENED_REPO_SERVER}:${HARDENED_REPO_DIR}/${RPM_ARCH}/RPMS/ ;                 \
	    fi ;                                                                                                              \
	    ssh ${HARDENED_REPO_SERVER} 'cd ${HARDENED_REPO_DIR} ; ${RPM_BUILD_REPO}' ;                                       \
	  else                                                                                                                \
	    mkdir -p ${HARDENED_REPO_DIR}/noarch/RPMS ${HARDENED_REPO_DIR}/${RPM_ARCH}/RPMS ;                                 \
	    if [ -n "${REPO_DELETE_OLD}" ] ; then                                                                             \
	      rm -f $(patsubst %, ${HARDENED_REPO_DIR}/noarch/RPMS/%-*, ${RPM_NAMES})                                         \
	            $(patsubst %, ${HARDENED_REPO_DIR}/noarch/RPMS/%-debuginfo-*, ${RPM_NAMES})                               \
	            $(patsubst %, ${HARDENED_REPO_DIR}/${RPM_ARCH}/RPMS/%-*, ${RPM_NAMES})                                    \
	            $(patsubst %, ${HARDENED_REPO_DIR}/${RPM_ARCH}/RPMS/%-debuginfo-*, ${RPM_NAMES}) ;                        \
	    fi ;                                                                                                              \
	    if ls -A rpm/RPMS/noarch/*.rpm > /dev/null 2>&1 ; then                                                            \
	      mv rpm/RPMS/noarch/*.rpm ${HARDENED_REPO_DIR}/noarch/RPMS/ ;                                                    \
	    fi ;                                                                                                              \
	    if ls -A rpm/RPMS/${RPM_ARCH}/*.rpm > /dev/null 2>&1 ; then                                                       \
	      mv rpm/RPMS/${RPM_ARCH}/*.rpm ${HARDENED_REPO_DIR}/${RPM_ARCH}/RPMS/ ;                                          \
	    fi ;                                                                                                              \
	    cd ${HARDENED_REPO_DIR} ; ${RPM_BUILD_REPO}; cd - >/dev/null ;                                                    \
	  fi                                                                                                                  \
	fi
