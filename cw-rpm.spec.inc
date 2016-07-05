# Default the License and URL if they are not already specified.
%{!?RPM_LICENSE: %define RPM_LICENSE "GPLv3+ with exceptions" }
%{!?RPM_URL: %define RPM_URL http://projectclearwater.org }

Version:        %{RPM_MAJOR_VERSION}
Release:        %{RPM_MINOR_VERSION}
License:        %{RPM_LICENSE}
URL:            %{RPM_URL}
Packager:       %{RPM_SIGNER_REAL} <%{RPM_SIGNER}>
AutoReqProv:    no

# Turn off the brp-python-bytecompile script
%global __os_install_post %(echo '%{__os_install_post}' | sed -e 's!/usr/lib[^[:space:]]*/brp-python-bytecompile[[:space:]].*$!!g')

%changelog
%(cat rpm/changelog)

# Template for debug information sub-package.
#
# This is a redefinition of the standard debug_package macro but with an
# additional Requires line to depend on the parent package at the correct
# version, and gdb.
%define cw_debug_package()\
%ifnarch noarch\
%global __debug_package 1\
%package debuginfo\
Summary: Debug information for package %{name}\
Group: Development/Debug\
AutoReqProv: 0\
Requires: gdb %{name} = %{version}-%{release}\
%description debuginfo\
This package provides debug information for package %{name}.\
Debug information is useful when developing applications that use this\
package or when debugging this package.\
%files debuginfo -f debugfiles.list\
%defattr(-,root,root)\
%endif\
%{nil}
