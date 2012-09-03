#!/usr/bin/perl
# $Id: Kickstart.pm,v 1.10 2012/07/02 00:41:34 deanh Exp $
package Kickie;

use strict;
use warnings;

use NetAddr::MAC;

use Schedule::At;
use Carp qw(croak);

our $VERSION = 0.1;

my $dhcpfile = q|/etc/dhcpd/hosts.conf|;

my $hosttemplate = <<'EODHCP';
host %MACADDR% { hardware ethernet %DHCPMACADDR%; fixed-address %IPADDR%; option host-name "%HOSTNAME%"; next-server %KSHOST%; filename "%FILENAME%"; }
EODHCP

my $cleartemplate = <<'EOCLEAR';
#wget -O /dev/null http://127.0.0.1/cgi-bin/complete.cgi?macaddr=%DHCPMACADDR%
# using tt.pl seems like a better option
tt.pl kscomplete macaddr %MACADDR%
EOCLEAR

=head1 NAME

Kickie - Abstract functions for setting up the pxe-boot (install) for a server (aka kickstart for RH)

=head1 SYNOPSIS

 use Kickie;

 Kickie::add(\%leaseparams,\%files,\%mergevalues);
 Kickie::remove($mac);

=head1 DESCRIPTION

This module provides abstracted functions for setting up the pxe-boot
of a server. When you pxe-boot then install the operating system, RedHat
calls this Kickstart. However this module aims to be general purpose enough
to not be specific to doing an installation or to RedHat.

=head1 PUBLIC FUNCTIONS

=head2 add(I<\%leaseparams>,I<\%files>,I<\%mergevalues>)

Adds a new machine for kickstarting based on the details in a hashref I<\%leaseparams>

The I<\%files> is a hash of where the key is the target filenames and the values is the content
of the files. Both the file names and templates will be merged with the values from mergevalues.

The I<\%mergevalues> hash is merged against the various templates as needed.

Here is an example of %leaseparams

=over 4

I<%leaseparms> = (
mac  => q|00112233aabbcc|,
ip   => q|192.0.1.15|,
gw   => q|192.0.1.1|,
name => q|hostname|,
next => q|192.0.15.1|,
file => q|bootfilename|,
time => 20*60,
);

=back

Where...

=over 4
B<mac> is the mac address of the host,
B<ip> is the ip address,
B<gw> is the router or 'gateway' address,
B<name> is the name of the host,
B<next> is the 'next-server' dhcp value - which is the tftp server
B<file> is the tftp filename value
B<time> is not the lease time, but the window of time (seconds) before removing the files etc
=back

B<next> defaults to the local eth0 ip, B<time> defaults to 20 mins

=cut

sub add {

    my $leaseparams = shift
      or croak 'need to have lease parameters';
    my $files = shift
      or croak 'need to have the list of files';
    my $mergevalues = shift
      or croak 'need to have the mergevalues';

    croak 'leaseparams must be a hashref'
      unless ref $leaseparams eq 'HASH';

    croak 'files must be a hashref'
      unless ref $files eq 'HASH';

    croak 'mergevalues must be a hashref'
      unless ref $mergevalues eq 'HASH';

    if ($leaseparams->{time}
        && defined $leaseparams->{time}) {

        croak 'time must be an integer'
            if $leaseparams->{time} !~ m/\d/;
    }

    # check all values are present
    for my $k (qw(mac ip name next file kshost)) {
        croak "$k is required"
          unless $leaseparams->{$k};
    }

    # copy lease params and files as we are going to modify them
    $leaseparams = {%$leaseparams};
    $files       = {%$files};

   # convert the mac address to a O::U::MAC object, which will also validate and normalise it
    $leaseparams->{mac} = NetAddr::MAC->new( $leaseparams->{mac} );

    $leaseparams->{mac}->is_eui48
      or croak 'Mac must be EUI48';

    $leaseparams->{mac}->is_unicast
      or croak 'Mac must be Unicast';

    my @filenames = _write_cfgs( $files, $mergevalues );

    $leaseparams->{_filenames} = \@filenames;

    _add_lease($leaseparams);

    _add_timer( $leaseparams->{mac}, $leaseparams->{time} || () );

    return 1;

}

=head2 remove(I<$mac>)

Removes the lease and associated files for the $mac ($mac is a scalar)

=cut

sub remove {

    # validate input
    my $mac = shift;

    # convert the mac address to a NetAddr::MAC object, which will also validate and normalise it
    $mac = NetAddr::MAC->new($mac)
      or croak "Mac was bad: $@";

    $mac->is_eui48
      or croak 'Mac must be EUI48';

    $mac->is_unicast
      or croak 'Mac must be Unicast';

    _cleanup($mac);

    _remove_lease($mac);

    return 1;

}

=head1 INTERNAL FUNCTIONS

=head2 _write_cfgs(I<\%files>, I<\%mergevalues>)

I<\%files> the filenames and files to be created in order to do the install.

I<\%mergevalues> is used to merge placeholders on the filenames and values

=cut

sub _write_cfgs {

    my $files       = shift;
    my $mergevalues = shift;

    my @filenames;

    # write out each file
    for my $k ( sort keys %{$files} ) {

        # merge the filename
        my $name = _merge( $k, $mergevalues );

        open my $fh, '>', $name
          or croak "Couldnt open cfg file $name for writing: $!";

        # write out the contents of the file
        print $fh _merge( $files->{$k}, $mergevalues );

        close $fh
          or croak "Couldnt close cfg file $name: $!";

        # preserve the filename for later
        push @filenames, $name;

    }

    return @filenames;

}

=head2 _write_leasefile(I<@lines>)

Writes I<@lines> out to the dhcp config file, then restarts dhcpd

=cut

sub _write_leasefile {

    my @lines = @_;

    open my $fh, '>', $dhcpfile
      or croak "Couldnt open $dhcpfile: $!";

    # strip trailing \n's and add a single \n after each line
    print $fh join( "\n", map { my $t = $_; $t =~ s/\n+$//; $t } @lines );
    print $fh "\n";    # cr at end of file

    close $fh
      or croak "Couldnt close $dhcpfile: $!";

    # save stdout, redirect it to dev null, then restore it after running
    # the command
    open my $stdcp, '>&', STDOUT;
    open STDOUT, '>', '/dev/null';

    system( '/sbin/service', 'dhcpd', 'restart' ) == 0
      or close STDOUT
      and open STDOUT, '>&', $stdcp
      and croak 'failed to restart dhcp after writing config file';

    close STDOUT;
    open STDOUT, '>&', $stdcp;

    return 1;

}

=head2 _slurp_file(I<$filename>)

Slurps I<$filename> and returns it

=cut

sub _slurp_file {

    my $filename = shift;

    croak "filename $filename isnt a file"
      unless -f $filename;

    open my $fh, '<', $filename
      or croak "Couldnt open $dhcpfile: $!";

    # Slurp it all in
    my @file = <$fh>;

    close $fh
      or croak "Couldnt close $dhcpfile: $!";

    return wantarray ? @file : join( q||, @file );

}

# just use this for testing

sub _set_dhcpfile {

	return unless $_[0];
	$dhcpfile = shift;

}

=head2 _add_lease(I<\%params>)

Adds a lease for the details provided in I<%params>. Required values are...

=over 4
 mac - the mac address as an NetAddr::MAC object
 ip - the ip address of the leasee
 gw - the router or gateway
 name - the hostname given to the leasee
 kshost - the tftp server ip (optional, defaults to dhcp server)
 file - the tftp boot file

=back

=cut

sub _add_lease {

    # recieve the info here
    my $params = shift;

    my $mac = $params->{mac};

    my %values = (

        MACADDR       => uc $mac->as_basic,
        DHCPMACADDR   => uc $mac->as_microsoft,
        IPADDR        => $params->{ip},
        HOSTNAME      => $params->{name},
        KSHOST        => $params->{kshost},
        PXEFILENAME   => $params->{file},
        EFI32FILENAME => $params->{efi32file} || $params->{file},
        EFI64FILENAME => $params->{efi64file} || $params->{file},

    );

    # convert this to a string for use in the regex
    $mac = $mac->as_basic;

# remove any existing entries
# it would be better to do this with a sub common to the remove function
# but i dont want to restart dhcp more than needed... and im not fussed to refactor

    my @dhcpdata = grep { !m/$mac/i } _slurp_file $dhcpfile;

    # push the lease entry
    push @dhcpdata, _merge( $hosttemplate, \%values );

    # push the other files we need to install
    for my $file ( @{ $params->{_filenames} } ) {
        push @dhcpdata, "# $values{MACADDR} file $file";
    }

    _write_leasefile(@dhcpdata);

    return 1

}

=head2 _cleanup($mac)

Removes the files written out to help the pxe-boot

I<$mac> is the mac address as an NetAddr::MAC object

=cut

sub _cleanup {

    # load and normalise mac
    my $mac = shift;
    $mac = NetAddr::MAC->new($mac)
      unless ref $mac;
    $mac = $mac->as_basic;

    # files to unlink
    my @files = map { m/$mac\s+file\s+(.+)/i; $1 }
                grep { m/$mac\s+file/i }
                _slurp_file $dhcpfile;

    # unlink the files as needed
    for my $file (@files) {
        chomp $file;
        next unless -f $file;
        unlink $file
          or croak "Couldnt remove $file: $!";
    }

    ## remove pending jobs for the mac address
    my %jobs = Schedule::At::getJobs(TAG => $mac);
    for my $job (values %jobs) {
        Schedule::At::remove( JOBID => $job->{JOBID})
    }


    return 1;
}

=head2 _add_timer($mac[,$time])

Adds an timer to clear the profile for I<$mac> (NetAddr::MAC object) in 20 mins or I<$time> seconds

Currently this sub works by dropping a job in to the at daemon

=cut

sub _add_timer {

    # load and normalise mac
    my $mac = shift;
    $mac = NetAddr::MAC->new($mac)
      unless ref $mac;

    my $time = shift || 20 * 60;

    # generate the command
    my $command = _merge(
        $cleartemplate,
        {

            # KSHOST      => $kshost,
            DHCPMACADDR => $mac->as_microsoft,
            MACADDR => $mac->as_basic,
        }
    );

    ## remove pending jobs for the mac address
    my %jobs = Schedule::At::getJobs(TAG => $mac->as_basic);
    for my $job (values %jobs) {
        Schedule::At::remove( JOBID => $job->{JOBID})
    }

    {    # kind of nasty, but we want schedule::At to make the job be in pwd /
        chdir q{/};

        # format for TIME is YYYYMMDDHHmm
        my @time = localtime( time + $time );    # add 20 mins
        Schedule::At::add(
            TIME => sprintf(
                '%d%02d%02d%02d%02d',
                1900 + $time[5],                 # year
                1 + $time[4],                    # month
                $time[3], $time[2], $time[1]
            ),
            COMMAND => $command,
            TAG     => $mac->as_basic,
          ) == 0
          or croak
          "Failed to schedule removal by atd: $!";  # S::A uses things backwards

    }

    return 1

}

=head2 _remove_lease(I<$mac>)

Removes the lease for the I<$mac> (NetAddr::MAC obj)

=cut

sub _remove_lease {

    my $mac = shift;

    # $mac is a hashref, so we will just override it
    # this wont kill it in the caller or anything.
    $mac = $mac->as_basic;

    # remove any existing entries
    my @dhcpdata = grep { !m/$mac/i } _slurp_file $dhcpfile;

    _write_leasefile(@dhcpdata);

    return 1

}

=head2 _merge(I<$tmpl>, I<\%values>)

  my $tmpl = q|myname: %NAME%|;
  my $result = _merge($tmpl, {name => 'Dean Hamstead'});

merges the I<$tmpl> scalar, with places holders of B<%KEY%>
where KEY is replaced with the value key'd from I<%values>.

KEY is uppercase in I<$tmpl> and also in I<%values>.

note that values is a hash ref.

=cut

sub _merge {

    my $tmpl   = shift;
    my $values = shift;
    return unless ( $tmpl or ref $values eq 'HASH' );

    1 while $tmpl =~ s/%([A-Z0-9]+)%/$values->{uc $1}/ge;

    return $tmpl;

}

1;

=head1 TODO

  There must be something more do be done

=head1 AUTHOR

Dean Hamstead (dean@fragfest.com.au)

=cut

__END__
