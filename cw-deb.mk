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
# DEB_COMPONENT       - name of overall component for manifest
#                       (e.g., sprout)
# DEB_MAJOR_VERSION   - major version number for deb package (e.g., 1.0)
# DEB_NAMES           - space-separated base names of deb packages
#                       (e.g., sprout sprout-dbg)
# DEB_ARCH (optional) - override deb architecture (defaults to this
#                       host's native architecture). E.g., set to all
#                       for arch-independent debs.

# Caller may also set the following:
# REPO_DIR             - path to repository to move Debian packages to (default
#                        is unset, meaning don't move packages)
# REPO_SERVER          - username and server to scp Debian pacakges to (default
#                        is unset, meaning move packages locally)
# CW_SIGNED            - whether to sign the generated Debian repository (default
#                        is unset, meaning don't sign; set to Y to sign).
#                        IMPORTANT: this signs the repo itself, which means that
#                        *all* packages in it are marked authentic, not just the
#                        ones we built just now. See http://wiki.debian.org/SecureApt
#                        for details.
# HARDENED_REPO_DIR    - path to the hardened repository to move Debian packages to
#                        (default is unset, meaning don't move packages)
# HARDENED_REPO_SERVER - username and server for the hardened repository to scp
#                        Debian pacakges to (default is unset, meaning move
#                        packages locally)

DEB_VERSION ?= ${DEB_MAJOR_VERSION}-$(shell date +%y%m%d.%H%M%S)
DEB_VERSION := $(DEB_VERSION)
ifeq ($(origin DEB_ARCH), undefined)
DEB_ARCH := $(shell dpkg --print-architecture)
endif

# Package maintainer, and owner of the signing key.
CW_SIGNER ?= maintainers@projectclearwater.org
CW_SIGNER_REAL := Project Clearwater Maintainers

# Commands to build a package repo.
CW_BUILD_REPO := dpkg-scanpackages --multiversion binary /dev/null > binary/Packages; \
                 gzip -9c binary/Packages >binary/Packages.gz;                        \
                 rm -f binary/Release binary/Release.gpg;                             \
                 apt-ftparchive -o APT::FTPArchive::Release::Codename=binary          \
                                                     release binary > binary/Release
ifeq ($(CW_SIGNED), Y)
CW_BUILD_REPO := $(CW_BUILD_REPO);                                                   \
                 gpg -abs -u $(CW_SIGNER) --output binary/Release.gpg binary/Release
endif

# thanks to http://stackoverflow.com/questions/1593051/how-to-programmatically-determine-the-current-checked-out-git-branch
GIT_BRANCH := $(shell branch=$$(git symbolic-ref -q HEAD); branch=$${branch\#\#refs/heads/}; branch=$${branch:-HEAD}; echo $$branch)

# Build and move to the repository server (if present).
.PHONY: deb-only
deb-only: deb-build deb-move deb-move-hardened

SHELL := bash
LICENSE := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))license

# Build the .deb files in ../*.deb
.PHONY: deb-build
deb-build:
	echo "${DEB_COMPONENT} (${DEB_VERSION}) unstable; urgency=low" >debian/changelog
	# If this is build from a git@github.com: URL then output Git instructions for accessing the build tree
	if [[ "$$(git config --get remote.origin.url)" =~ ^git@github.com: ]]; then\
		echo "  * build from $$(git config --get remote.origin.url|sed -e 's#^\([^:]*\):\([^/]*\)\([^.]*\)[.]git#http://\1/\2\3/tree/#')$$(git rev-parse HEAD)" >>debian/changelog;\
		echo "    Use Git to access the source code for this build as follows:" >>debian/changelog;\
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
	echo $(LICENSE)
	echo "" >> debian/copyright
	cat $(LICENSE) >> debian/copyright
else
	@printf "*******************************************************************************\n*\n* LICENSE file ($(LICENSE)) is missing\n*\n*******************************************************************************\n"
	@exit 1
endif
	debuild --no-lintian -b -uc -us

# Move to repository.  Must be the same make invocation as deb-build, unless
# DEB_VERSION is specified explicitly.  If REPO_SERVER is specified,
# known_hosts on this server must include $REPO_SERVER's server key, and
# authorized_keys on $REPO_SERVER must include this server's user key.
# ssh-copy-id can be used to achieve this.
.PHONY: deb-move
deb-move:
	@if [ "${REPO_DIR}" != "" ] ; then                                                                                                \
	  if [ "${REPO_SERVER}" != "" ] ; then                                                                                            \
	    echo Copying to directory ${REPO_DIR} on repo server ${REPO_SERVER}... ;                                                      \
	    ssh ${REPO_SERVER} mkdir -p '${REPO_DIR}/binary' ;                                                                            \
	    if [ -n "${REPO_DELETE_OLD}" ] ; then                                                                                         \
	      ssh ${REPO_SERVER} rm -f $(patsubst %, '${REPO_DIR}/binary/%_*', ${DEB_NAMES}) ;                                            \
	    fi ;                                                                                                                          \
	    scp $(patsubst %, ../%_${DEB_VERSION}_${DEB_ARCH}.deb, ${DEB_NAMES}) ${REPO_SERVER}:${REPO_DIR}/binary/ ;                     \
	    ssh ${REPO_SERVER} 'cd ${REPO_DIR} ; ${CW_BUILD_REPO}' ;                                                                      \
	  else                                                                                                                            \
	    mkdir -p ${REPO_DIR}/binary ;                                                                                                 \
	    if [ -n "${REPO_DELETE_OLD}" ] ; then                                                                                         \
	      rm -f $(patsubst %, ${REPO_DIR}/binary/%_*, ${DEB_NAMES}) ;                                                                 \
	    fi ;                                                                                                                          \
	    for deb in ${DEB_NAMES} ; do mv ../$${deb}_${DEB_VERSION}_${DEB_ARCH}.deb ${REPO_DIR}/binary; done ;                          \
	    cd ${REPO_DIR} ; ${CW_BUILD_REPO}; cd - >/dev/null ;                                                                          \
	  fi                                                                                                                              \
	fi

.PHONY: deb-move-hardened
deb-move-hardened:
	@if [ "${HARDENED_REPO_DIR}" != "" ] ; then                                                                                                                   \
	  if [ "${HARDENED_REPO_SERVER}" != "" ] ; then                                                                                                               \
	    echo Copying to directory ${HARDENED_REPO_DIR} on repo server ${HARDENED_REPO_SERVER}... ;                                                                \
	    ssh ${HARDENED_REPO_SERVER} mkdir -p '${HARDENED_REPO_DIR}/binary' ;                                                                                      \
	    if [ -n "${REPO_DELETE_OLD}" ] ; then                                                                                                                     \
	      ssh ${HARDENED_REPO_SERVER} rm -f $(patsubst %, '${HARDENED_REPO_DIR}/binary/%_*', ${DEB_NAMES}) ;                                                      \
	    fi ;                                                                                                                                                      \
	    scp $(patsubst %, ../%_${DEB_VERSION}_${DEB_ARCH}.deb, ${DEB_NAMES}) ${HARDENED_REPO_SERVER}:${HARDENED_REPO_DIR}/binary/ ;                               \
	    ssh ${HARDENED_REPO_SERVER} 'cd ${HARDENED_REPO_DIR} ; ${CW_BUILD_REPO}' ;                                                                                \
	  else                                                                                                                                                        \
	    mkdir -p ${HARDENED_REPO_DIR}/binary ;                                                                                                                    \
	    if [ -n "${REPO_DELETE_OLD}" ] ; then                                                                                                                     \
	      rm -f $(patsubst %, ${HARDENED_REPO_DIR}/binary/%_*, ${DEB_NAMES}) ;                                                                                    \
	    fi ;                                                                                                                                                      \
	    for deb in ${DEB_NAMES} ; do mv ../$${deb}_${DEB_VERSION}_${DEB_ARCH}.deb ${HARDENED_REPO_DIR}/binary; done ;                                             \
	    cd ${HARDENED_REPO_DIR} ; ${CW_BUILD_REPO}; cd - >/dev/null ;                                                                                             \
	  fi                                                                                                                                                          \
	 fi
