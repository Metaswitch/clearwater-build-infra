# Debian package makefile
#
# Provides common logic for creating and pushing Debian packages.
#
# Project Clearwater - IMS in the Cloud
# Copyright (C) 2013  Metaswitch Networks Ltd
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
# PKG_COMPONENT or DEB_COMPONENT (DEB_COMPONENT takes precedence)
#                      - name of overall component for manifest
#                        (e.g., sprout)
# PKG_MAJOR_VERSION or DEB_MAJOR_VERSION (DEB_MAJOR_VERSION takes precedence)
#                      - major version number for package (e.g., 1.0)
# PKG_NAMES or DEB_NAMES (DEB_NAMES takes precedence)
#                      - space-separated base names of packages
#                        (e.g., sprout sprout-dbg)

# Caller may also set the following:
# PKG_MINOR_VERSION or DEB_MINOR_VERSION (DEB_MINOR_VERSION takes precedence)
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
# We can't just do a straight include, because we need to handle the case where the pwd is not the root of sprout (e.g. when building plugins)
include $(shell dirname $(lastword $(MAKEFILE_LIST)))/cw-pkg.mk

# Default DEB_* from PKG_*
DEB_COMPONENT ?= $(PKG_COMPONENT)
DEB_MAJOR_VERSION ?= $(PKG_MAJOR_VERSION)
DEB_MINOR_VERSION ?= $(PKG_MINOR_VERSION)
DEB_NAMES ?= $(PKG_NAMES)

# Commands to build a package repo.
DEB_BUILD_REPO := dpkg-scanpackages --multiversion binary > binary/Packages; \
                  gzip -9c binary/Packages >binary/Packages.gz;                        \
                  rm -f binary/Release binary/Release.gpg;                             \
                  apt-ftparchive -o APT::FTPArchive::Release::Codename=binary          \
                                                      release binary > binary/Release
ifeq ($(CW_SIGNED), Y)
DEB_BUILD_REPO := $(DEB_BUILD_REPO);                                                   \
                 gpg -abs -u $(CW_SIGNER) --output binary/Release.gpg binary/Release
endif

# Build and move to the repository server (if present).
.PHONY: deb-only
deb-only: deb-build deb-move deb-move-hardened

# Build the .deb files in ../*.deb
.PHONY: deb-build
deb-build:
	echo "${DEB_COMPONENT} (${DEB_MAJOR_VERSION}-${DEB_MINOR_VERSION}) unstable; urgency=low" >debian/changelog
	# If this is built from a git@github.com: URL then output Git instructions for accessing the build tree
	if [[ "$$(git config --get remote.origin.url)" =~ ^git@github.com: ]]; then\
		echo "  * build from $$(git config --get remote.origin.url|sed -e 's#^git@\([^:]*\):\([^/]*\)\([^.]*\)[.]git#https://\1/\2\3/tree/#')$$(git rev-parse HEAD)" >>debian/changelog;\
		echo "    Use Git to access the source code for this build as follows:" >>debian/changelog;\
		echo "      $$ git config --global url.\"https://github.com/\".insteadOf git@github.com:" >>debian/changelog;\
		echo "      $$ git clone --recursive $$(git config --get remote.origin.url)" >>debian/changelog;\
		echo "      Cloning into '$$(git config --get remote.origin.url|sed -e 's#^\([^:]*\):\([^/]*\)/\([^.]*\)[.]git#\3#')'..." >>debian/changelog;\
		echo "        ..."  >>debian/changelog;\
		echo "      $$ cd $$(git config --get remote.origin.url|sed -e 's#^\([^:]*\):\([^/]*\)/\([^.]*\)[.]git#\3#')" >>debian/changelog;\
		echo "      $$ git checkout -q $$(git rev-parse HEAD)" >>debian/changelog;\
		echo "      $$ git submodule update --init" >>debian/changelog;\
		echo "        ..."  >>debian/changelog;\
		echo "      $$"  >>debian/changelog;\
        else\
		echo "  * build from revision $$(git rev-parse HEAD)" >>debian/changelog;\
	fi
	echo " -- $(CW_SIGNER_REAL) <$(CW_SIGNER)>  $$(date -R)" >>debian/changelog
ifneq ($(wildcard $(LICENSE)),)
	if [ -e debian/copyright.repo ]; then\
		cp debian/copyright.repo debian/copyright;\
		echo "" >> debian/copyright;\
	        echo "Files: *" >> debian/copyright;\
	        echo "Copyright: Metaswitch Networks" >> debian/copyright;\
	        echo "License: GPL-3+ with OpenSSL exception" >> debian/copyright;\
		cat $(LICENSE) >> debian/copyright;\
	fi
else
	@printf "*******************************************************************************\n*\n* LICENSE file ($(LICENSE)) is missing\n*\n*******************************************************************************\n"
	@exit 1
endif
	debuild --no-lintian -b -uc -us

# Move to repository.  Must be the same make invocation as deb-build, unless
# DEB_MINOR_VERSION is specified explicitly.  If REPO_SERVER is specified,
# known_hosts on this server must include $REPO_SERVER's server key, and
# authorized_keys on $REPO_SERVER must include this server's user key.
# ssh-copy-id can be used to achieve this.

# Shell globs that match the specified packages, and their associated debug
# packages, respectively. Note that whike all the items in the first glob
# should match something, this is not true for the second glob (as not all
# packages have debug packgages). The code below handles this by usng ls to
# determine what the matches are, and only carrying on if there are some
# matches.
#
# Some existing projects explicitly list their debug packages in DEB_NAMES.
# Th3e code copes with this. If we are moving to a remote server, we delete the
# packages after a successful copy as this avoid copying any debug packages
# twice.
LOCAL_DEB_GLOB := $(patsubst %, ../%_${DEB_MAJOR_VERSION}-${DEB_MINOR_VERSION}_*.deb, ${DEB_NAMES})
LOCAL_DEB_DBG_GLOB := $(patsubst %, ../%-dbg_${DEB_MAJOR_VERSION}-${DEB_MINOR_VERSION}_*.deb, ${DEB_NAMES})

.PHONY: deb-move
deb-move:
	@if [ "${REPO_DIR}" != "" ] ; then                                                                                                               \
	  if [ "${REPO_SERVER}" != "" ] ; then                                                                                                           \
	    echo Copying to directory ${REPO_DIR} on repo server ${REPO_SERVER}... ;                                                                     \
	    ssh ${REPO_SERVER} mkdir -p '${REPO_DIR}/binary' ;                                                                                           \
	    if [ -n "${REPO_DELETE_OLD}" ] ; then                                                                                                        \
	      ssh ${REPO_SERVER} rm -f $(patsubst %, '${REPO_DIR}/binary/%_*', ${DEB_NAMES})                                                             \
	                               $(patsubst %, '${REPO_DIR}/binary/%-dbg_*', ${DEB_NAMES});                                                        \
	    fi ;                                                                                                                                         \
	    scp ${LOCAL_DEB_GLOB} ${REPO_SERVER}:${REPO_DIR}/binary/ && rm ${LOCAL_DEB_GLOB} ;                                                           \
	    debug_packages=$$(ls -A ${LOCAL_DEB_DBG_GLOB} 2>/dev/null);                                                                                  \
	    if [ -n "$$debug_packages" ]; then                                                                                                           \
	      scp $$debug_packages ${REPO_SERVER}:${REPO_DIR}/binary/ && rm $$debug_packages ;                                                           \
	    fi ;                                                                                                                                         \
	    ssh ${REPO_SERVER} 'cd ${REPO_DIR} ; ${DEB_BUILD_REPO}' ;                                                                                    \
	  else                                                                                                                                           \
	    mkdir -p ${REPO_DIR}/binary ;                                                                                                                \
	    if [ -n "${REPO_DELETE_OLD}" ] ; then                                                                                                        \
	      rm -f $(patsubst %, ${REPO_DIR}/binary/%_*, ${DEB_NAMES}) ;                                                                                \
	      rm -f $(patsubst %, ${REPO_DIR}/binary/%-dbg_*, ${DEB_NAMES}) ;                                                                            \
	    fi ;                                                                                                                                         \
	    mv ${LOCAL_DEB_GLOB} ${REPO_DIR}/binary;                                                                                                     \
	    debug_packages=$$(ls -A ${LOCAL_DEB_DBG_GLOB} 2>/dev/null);                                                                                  \
	    if [ -n "$$debug_packages" ]; then                                                                                                           \
	      mv $$debug_packages ${REPO_DIR}/binary/ ;                                                                                                  \
	    fi ;                                                                                                                                         \
	    cd ${REPO_DIR} ; ${DEB_BUILD_REPO}; cd - >/dev/null ;                                                                                        \
	  fi ;                                                                                                                                           \
	fi ;

.PHONY: deb-move-hardened
deb-move-hardened:
	@if [ "${HARDENED_REPO_DIR}" != "" ] ; then                                                                                                      \
	  if [ "${HARDENED_REPO_SERVER}" != "" ] ; then                                                                                                  \
	    echo Copying to directory ${HARDENED_REPO_DIR} on repo server ${HARDENED_REPO_SERVER}... ;                                                   \
	    ssh ${HARDENED_REPO_SERVER} mkdir -p '${HARDENED_REPO_DIR}/binary' ;                                                                         \
	    if [ -n "${REPO_DELETE_OLD}" ] ; then                                                                                                        \
	      ssh ${HARDENED_REPO_SERVER} rm -f $(patsubst %, '${HARDENED_REPO_DIR}/binary/%_*', ${DEB_NAMES})                                           \
	                                        $(patsubst %, '${HARDENED_REPO_DIR}/binary/%-dbg_*', ${DEB_NAMES}) ;                                     \
	    fi ;                                                                                                                                         \
	    scp $(LOCAL_DEB_GLOB) ${HARDENED_REPO_SERVER}:${HARDENED_REPO_DIR}/binary/ && rm ${LOCAL_DEB_GLOB};                                          \
	    debug_packages=$$(ls -A ${LOCAL_DEB_DBG_GLOB} 2>/dev/null);                                                                                  \
	    if [ -n "$$debug_packages" ]; then                                                                                                           \
	      scp $$debug_packages ${HARDENED_REPO_SERVER}:${HARDENED_REPO_DIR}/binary/ && rm $$debug_packages;                                          \
	    fi ;                                                                                                                                         \
	    ssh ${HARDENED_REPO_SERVER} 'cd ${HARDENED_REPO_DIR} ; ${DEB_BUILD_REPO}' ;                                                                  \
	  else                                                                                                                                           \
	    mkdir -p ${HARDENED_REPO_DIR}/binary ;                                                                                                       \
	    if [ -n "${REPO_DELETE_OLD}" ] ; then                                                                                                        \
	      rm -f $(patsubst %, ${HARDENED_REPO_DIR}/binary/%_*, ${DEB_NAMES})                                                                         \
	            $(patsubst %, ${HARDENED_REPO_DIR}/binary/%-dbg_*, ${DEB_NAMES}) ;                                                                   \
	    fi ;                                                                                                                                         \
	    mv ${LOCAL_DEB_GLOB} ${HARDENED_REPO_DIR}/binary;                                                                                            \
	    debug_packages=$$(ls -A ${LOCAL_DEB_DBG_GLOB} 2>/dev/null);                                                                                  \
	    if [ -n "$$debug_packages" ]; then                                                                                                           \
	      mv $$debug_packages ${HARDENED_REPO_DIR}/binary/ ;                                                                                         \
	    fi ;                                                                                                                                         \
	    cd ${HARDENED_REPO_DIR} ; ${DEB_BUILD_REPO}; cd - >/dev/null ;                                                                               \
	  fi ;                                                                                                                                           \
	 fi ;
