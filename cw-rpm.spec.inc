Version:        %{PKG_MAJOR_VERSION}
Release:        %{PKG_MINOR_VERSION}
License:        "GPLv3+ with exceptions"
URL:            http://projectclearwater.org
AutoReqProv:    no

# Turn off the brp-python-bytecompile script
%global __os_install_post %(echo '%{__os_install_post}' | sed -e 's!/usr/lib[^[:space:]]*/brp-python-bytecompile[[:space:]].*$!!g')

%changelog
%(cat rpm/changelog)
