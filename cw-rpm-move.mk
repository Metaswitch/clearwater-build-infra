# RPM package makefile
#
# Provides common logic for pushing RPM packages.
#
# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

# Caller must set the following:
# PKG_NAMES or RPM_NAMES (RPM_NAMES takes precedence)
#                      - space-separated base names of packages
#                        (e.g., sprout). For new projects this should not list
#                        the debug packages explicitly (the build
#                        infrastructure will spot them and install then and
#                        hanle appropriately).

# Caller may also set the following:
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
RPM_NAMES ?= $(PKG_NAMES)

RPM_ARCH := $(shell rpmbuild -E %{_arch} 2>/dev/null)
RPM_NOARCH_DIR ?= rpm/RPMS/noarch
RPM_ARCH_DIR ?= rpm/RPMS/${RPM_ARCH}

# Commands to build an RPM package repo.
RPM_BUILD_REPO := createrepo .
ifeq ($(CW_SIGNED), Y)
RPM_BUILD_REPO := $(RPM_BUILD_REPO) ; \
                  gpg -abs -u $(CW_SIGNER) repodata/repomd.xml
endif

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
	    if ls -A ${RPM_NOARCH_DIR}/*.rpm > /dev/null 2>&1; then                                                           \
	      scp ${RPM_NOARCH_DIR}/*.rpm ${REPO_SERVER}:${REPO_DIR}/noarch/RPMS/ ;                                           \
	    fi ;                                                                                                              \
	    if ls -A ${RPM_ARCH_DIR}/*.rpm > /dev/null 2>&1; then                                                             \
	      scp ${RPM_ARCH_DIR}/*.rpm ${REPO_SERVER}:${REPO_DIR}/${RPM_ARCH}/RPMS/ ;                                        \
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
	    if ls -A ${RPM_NOARCH_DIR}/*.rpm > /dev/null 2>&1 ; then                                                          \
	      mv ${RPM_NOARCH_DIR}/*.rpm ${REPO_DIR}/noarch/RPMS/ ;                                                           \
	    fi ;                                                                                                              \
	    if ls -A ${RPM_ARCH_DIR}/*.rpm > /dev/null 2>&1 ; then                                                            \
	      mv ${RPM_ARCH_DIR}/*.rpm ${REPO_DIR}/${RPM_ARCH}/RPMS/ ;                                                        \
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
	    if ls -A ${RPM_NOARCH_DIR}/*.rpm > /dev/null 2>&1; then                                                           \
	      scp ${RPM_NOARCH_DIR}/*.rpm ${HARDENED_REPO_SERVER}:${HARDENED_REPO_DIR}/noarch/RPMS/ ;                         \
	    fi ;                                                                                                              \
	    if ls -A ${RPM_ARCH_DIR}/*.rpm > /dev/null 2>&1; then                                                             \
	      scp ${RPM_ARCH_DIR}/*.rpm ${HARDENED_REPO_SERVER}:${HARDENED_REPO_DIR}/${RPM_ARCH}/RPMS/ ;                      \
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
	    if ls -A ${RPM_NOARCH_DIR}/*.rpm > /dev/null 2>&1 ; then                                                          \
	      mv ${RPM_NOARCH_DIR}/*.rpm ${HARDENED_REPO_DIR}/noarch/RPMS/ ;                                                  \
	    fi ;                                                                                                              \
	    if ls -A ${RPM_ARCH_DIR}/*.rpm > /dev/null 2>&1 ; then                                                            \
	      mv ${RPM_ARCH_DIR}/*.rpm ${HARDENED_REPO_DIR}/${RPM_ARCH}/RPMS/ ;                                               \
	    fi ;                                                                                                              \
	    cd ${HARDENED_REPO_DIR} ; ${RPM_BUILD_REPO}; cd - >/dev/null ;                                                    \
	  fi                                                                                                                  \
	fi
