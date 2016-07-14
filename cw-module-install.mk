# Each submodule installs itself, thus updating timestamps of include and
# library files.
#
# To work around this, we keep a backup of the install dir with correct checksums,
# and replace the install dir with the ones with the correct checksums.
BAK_INSTALL_DIR := ${ROOT}/build/module-install/usr

# sync_install can be called repeatedly, idempotently. Each time it will
# make the install directory have the minimum correct timestamps.
.PHONY: sync_install
sync_install:

	mkdir -p ${BAK_INSTALL_DIR}

	# First update the backup install dir.
	#
	# We use rsync to update all the files whose contents have changed, using
	# checksums instead of timestamps
	rsync --links -v -r --checksum --delete ${INSTALL_DIR}/ ${BAK_INSTALL_DIR}/

	# Now update the install dir. First remove the old one with later timestamps
	rm -rf ${INSTALL_DIR}

	# Copy the backup into it's place. This has the same files, but with earlier
	# timestamps
	cp -r --preserve=timestamps ${BAK_INSTALL_DIR}/ ${INSTALL_DIR}/
