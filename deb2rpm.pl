#!/usr/bin/perl
#
# Tool to convert Clearwater Debian control files into (approximate) RPM spec files
#
# Run from the root of the repo (i.e. the parent of build-infra) with no parameters
#
# Not intended for ongoing use - just for initial migration
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

use strict;
use warnings;

my $filename = "debian/control";
open(my $in, "<", $filename) or die "Could not open $filename for reading";

sub write_spec {
  my($package, $build_depends, $description, $architecture, $depends, $recommends, $suggests) = @_;
  my $filename = "rpm/$package.spec";
  if (-e $filename) {
    print "Not creating $filename - already exists\n";
  } else {
    print "Creating $filename for package $package\n";
    open(my $out, ">", $filename) or die "Could not open $filename for writing";
    print $out <<EOF;
Name:           $package
Summary:        $description
EOF
    if (defined($architecture) && ($architecture eq "all")) {
      print $out "BuildArch:      noarch\n";
    }
    if (defined($build_depends)) {
      $build_depends =~ s/([^() ]*) \(([<=>]+) +([^() ]+)\)/$1 $2 $3/g;
      $build_depends =~ s/ *, */ /g;
      $build_depends =~ s/debhelper>=8.0.0//g;
      $build_depends =~ s/python2.7/python2-devel python-virtualenv/g;
      $build_depends =~ s/ +/ /g;
      $build_depends =~ s/(^ | $)//g;
      print $out "BuildRequires:  $build_depends\n";
    }
    $depends = $depends // "";
    $depends = "redhat-lsb-core $depends"; # All packages (or at least any that have init.d scripts) need LSB
    $depends =~ s/([^() ]*) +\(([<=>]+) +([^() ]+)\)/$1 $2 $3/g;
    $depends =~ s/ *, */ /g;
    $depends =~ s/(^ | $)//g;
    print $out "Requires:       $depends\n";
    if (defined($recommends)) {
      $recommends =~ s/([^() ]*) +\(([<=>]+) +([^() ]+)\)/$1 $2 $3/g;
      $recommends =~ s/ *, */ /g;
      $recommends =~ s/(^ | $)//g;
      # Recommends isn't supported in our version of rpm - so commented out
      print $out "#Recommends:     $recommends\n";
    }
    if (defined($suggests)) {
      $suggests =~ s/([^() ]*) +\(([<=>]+) +([^() ]+)\)/$1 $2 $3/g;
      $suggests =~ s/ *, */ /g;
      $suggests =~ s/(^ | $)//g;
      # Suggests isn't supported in our version of rpm - so commented out
      print $out "#Suggests:       $suggests\n";
    }
    print $out <<EOF;

%include %{rootdir}/build-infra/cw-rpm.spec.inc

%description
$description

%install
. %{rootdir}/build-infra/cw-rpm-utils $package %{rootdir} %{buildroot}
setup_buildroot
EOF
    if (-e "debian/$package.install") {
      print $out "install_to_buildroot < %{rootdir}/debian/$package.install\n";
    }
    if (-e "debian/$package.dirs") {
      print $out "dirs_to_buildroot < %{rootdir}/debian/$package.dirs\n";
    }
    if (-e "debian/$package.init.d") {
      print $out "copy_to_buildroot debian/$package.init.d /etc/init.d/$package\n";
    }
    if (-e "debian/$package.logrotate") {
      print $out "copy_to_buildroot debian/$package.logrotate /etc/logrotate.d/$package\n";
    }
    if (-e "debian/$package.preinst") {
      print " - Check debian/$package.preinst!\n";
      print $out "echo Check debian/$package.preinst and remove this message! >&2 ; exit 1\n";
    }
    if (-e "debian/$package.postinst") {
      print " - Check debian/$package.postinst!\n";
      print $out "echo Check debian/$package.postinst and remove this message! >&2 ; exit 1\n";
    }
    if (-e "debian/$package.prerm") {
      print " - Check debian/$package.prerm!\n";
      print $out "echo Check debian/$package.prerm and remove this message! >&2 ; exit 1\n";
    }
    if (-e "debian/$package.postrm") {
      print " - Check debian/$package.postrm!\n";
      print $out "echo Check debian/$package.postrm and remove this message! >&2 ; exit 1\n";
    }
    if (-e "debian/$package.triggers") {
      print " - Check debian/$package.triggers!\n";
      print $out "echo Check debian/$package.triggers and remove this message! >&2 ; exit 1\n";
    }
    print $out <<EOF;
build_files_list > $package.files

%files -f $package.files
EOF
    close $out;
  }
}

my $build_depends;
my $package;
my $description;
my $architecture;
my $depends;
my $recommends;
my $suggests;

while (my $line = <$in>) {
  chomp $line;
  if ($line =~ /^Build-Depends: (.*)$/) {
    $build_depends = $1;
  } elsif ($line =~ /^Package: (.*)$/) {
    if (defined $package) {
      write_spec($package, $build_depends, $description, $architecture, $depends, $recommends, $suggests);
      undef $description;
      undef $architecture;
      undef $depends;
      undef $recommends;
      undef $suggests;
    }
    $package = $1;
  } elsif ($line =~ /^Description: (.*)$/) {
    $description = $1;
  } elsif ($line =~ /^Architecture: (.*)$/) {
    $architecture = $1;
  } elsif ($line =~ /^Depends: (.*)$/) {
    $depends = $1;
  } elsif ($line =~ /^Recommends: (.*)$/) {
    $recommends = $1;
  } elsif ($line =~ /^Suggests: (.*)$/) {
    $suggests = $1;
  }
}

if (defined $package) {
  write_spec($package, $build_depends, $description, $architecture, $depends, $recommends, $suggests);
}

close $in;
