# Each submodule installs itself, thus updating timestamps of include and
# library files.
#
# To work around this, we install them elsewhere, and then synchronize them to allow
# incremental builds to work
PRE_ROOT := ${ROOT}/build/module-install
PRE_PREFIX := ${PRE_ROOT}/usr
PRE_INSTALL_DIR := ${PRE_PREFIX}
PRE_INCLUDE_DIR := ${PRE_INSTALL_DIR}/include
PRE_LIB_DIR := ${PRE_INSTALL_DIR}/lib

.PHONY: sync_install
sync_install:
	# pkg-config generates files which explcitly refer to the pre synchronized
	# directory, so we need to fix them up
	sed -e 's/build\/module-install\///g' -i ${PRE_INSTALL_DIR}/lib/pkgconfig/*.pc

	# rsync using checksums, as the modification time is wrong. This may lead
	# to false negatives, but they are very unlikely and tricky to workaround
	rsync --links -v -r --checksum ${PRE_INSTALL_DIR}/ ${INSTALL_DIR}/

