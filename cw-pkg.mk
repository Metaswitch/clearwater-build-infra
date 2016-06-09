# Common packaging makefile
#
# Provides common setup for packages (both Debian and RPM).
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

ifeq ($(origin PKG_MINOR_VERSION), undefined)
# Need to use := here so that we evaluate it now, not each time we need it
PKG_MINOR_VERSION := $(shell date +%y%m%d.%H%M%S)
endif

# Package maintainer, and owner of the signing key.
CW_SIGNER ?= maintainers@projectclearwater.org
CW_SIGNER_REAL := Project Clearwater Maintainers

# thanks to http://stackoverflow.com/questions/1593051/how-to-programmatically-determine-the-current-checked-out-git-branch
GIT_BRANCH := $(shell branch=$$(git symbolic-ref -q HEAD); branch=$${branch\#\#refs/heads/}; branch=$${branch:-HEAD}; echo $$branch)

SHELL := bash
LICENSE := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))LICENSE
