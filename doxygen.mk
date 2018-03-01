# Copyright (C) Metaswitch Networks 2017
# If license terms are provided to you in a COPYING file in the root directory
# of the source code repository by which you are accessing this code, then
# the license outlined in that COPYING file applies to your use.
# Otherwise no rights are granted except for those provided to you by
# Metaswitch Networks in a separate written agreement.

.PHONY: doxygen
doxygen:
	doxygen -g ${BUILD_DIR}/Doxyfile
	sed -i -e "s/^RECURSIVE .*/RECURSIVE = YES/g" ${BUILD_DIR}/Doxyfile

	sed -i -e "s/^OUTPUT_DIRECTORY .*/OUTPUT_DIRECTORY = ${DOCS_DIR}/g" ${BUILD_DIR}/Doxyfile
	sed -i -e "s/^PROJECT_NAME .*/PROJECT_NAME = ${PROJECT_NAME}/g" ${BUILD_DIR}/Doxyfile
	sed -i -e "s/^PROJECT_NUMBER .*/PROJECT_NUMBER = ${git rev-parse HEAD}/g" ${BUILD_DIR}/Doxyfile

	sed -i -e "s/^FORCE_LOCAL_INCLUDES .*/FORCE_LOCAL_INCLUDES = YES/g" ${BUILD_DIR}/Doxyfile
	sed -i -e "s/^EXTRACT_ALL .*/EXTRACT_ALL = YES/g" ${BUILD_DIR}/Doxyfile
	sed -i -e "s/^EXTRACT_PRIVATE .*/EXTRACT_PRIVATE = YES/g" ${BUILD_DIR}/Doxyfile
	sed -i -e "s/^EXTRACT_PACKAGE .*/EXTRACT_PACKAGE = YES/g" ${BUILD_DIR}/Doxyfile
	sed -i -e "s/^EXTRACT_STATIC .*/EXTRACT_STATIC = YES/g" ${BUILD_DIR}/Doxyfile
	sed -i -e "s/^EXTRACT_LOCAL_METHODS .*/EXTRACT_LOCAL_METHODS = YES/g" ${BUILD_DIR}/Doxyfile
	sed -i -e "s/^EXTRACT_ANON_NSPACES .*/EXTRACT_ANON_NSPACES = YES/g" ${BUILD_DIR}/Doxyfile
	sed -i -e "s/^BUILTIN_STL_SUPPORT .*/BUILTIN_STL_SUPPORT = YES/g" ${BUILD_DIR}/Doxyfile
	
	sed -i -e "s/^LATEX_OUTPUT .*/LATEX_OUTPUT = NO/g" ${BUILD_DIR}/Doxyfile

	doxygen ${BUILD_DIR}/Doxyfile

