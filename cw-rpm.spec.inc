Version:        %{RPM_MAJOR_VERSION}
Release:        %{RPM_MINOR_VERSION}
Packager:       %{RPM_SIGNER_REAL} <%{RPM_SIGNER}>
AutoReqProv:    no

# Turn off the brp-python-bytecompile script
%global __os_install_post %(echo '%{__os_install_post}' | sed -e 's!/usr/lib[^[:space:]]*/brp-python-bytecompile[[:space:]].*$!!g')

%changelog
%(cat rpm/changelog)
