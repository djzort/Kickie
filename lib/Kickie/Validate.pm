#!/usr/bin/perl

package Kickie::Validate;

use strict;
use warnings;

use Carp qw(croak);
use NetAddr::MAC;

use List::Util qw( first );
use base qw( Exporter );
use vars qw( $VERSION %EXPORT_TAGS @EXPORT_OK );
$VERSION = (qw$Revision: 1.22 $)[1];

%EXPORT_TAGS = ();

Exporter::export_ok_tags( keys %EXPORT_TAGS );

my $YUM_REPOS='repo.optusnet.com.au/mrepo';

=head1 NAME

Kickie::Validate - Validates kickstart data

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=head2 new(%config)

The I<new> method (unsuprisingly) creates the O::K::Validate object,
youll need to provide it with the local configuration as the I<%config>

I<%config> should contain...

=over 4

    self => $transobject,
    os_versions => \%os_versions,
    chassis_config => \%chassis_config,

=back

It will check all the data and die if anything is amuck - So make
sure you catch it!

=cut

sub new {

    my ( $p, %a ) = @_;
    my $c = ref($p) || $p;

    croak 'Need trans option to create ' . __PACKAGE__
        unless $a{trans} and ref $a{trans};

    croak 'Need os_versions option to create ' . __PACKAGE__
        unless $a{os_versions} and ref $a{os_versions};

    croak 'Need chassis_config option to create ' . __PACKAGE__
        unless $a{chassis_config} and ref $a{chassis_config};

    my $self = bless {
                      trans          => $a{trans},
                      os_versions    => $a{os_versions},
                      chassis_config => $a{chassis_config},
                      _saved         => {},
                    },
                $c;

    _init($self) if $a{init};

    return $self;

}

=head2 get_arch

returns the architecture

=cut

sub get_arch { return _check_arch( shift ) }

=head2 get_bootfiles

returns the bootfiles hash

=cut

sub get_bootfiles { return _check_bootfiles( shift ) }

=head2 get_bootloader

returns the bootloader

=cut

sub get_bootloader { return _check_bootloader( shift ) }

=head2 get_bootloaderappend

returns the bootloader append string

=cut

sub get_bootloaderappend { return _check_bootloaderappend( shift ) }

=head2 get_bootopt

returns the boot options string

=cut

sub get_bootopt { return _check_bootopt( shift ) }

=head2 get_disk_layout

returns the disk device layout

=cut

sub get_disk_layout { return _check_disk_layout( shift ) }

=head2 get_disk_extrapart

returns the disk extrapart info

=cut

sub get_disk_extrapart { return _check_disk_extrapart( shift ) }


=head2 get_gateway

returns the gateway (default router)

=cut

sub get_gateway { return _num2ip( _check_gateway( shift ) ) }

=head2 get_hostname

returns the hostname

=cut

sub get_hostname { return _check_hostname( shift ) }

=head2 get_ipaddr

returns the ip address

=cut

sub get_ipaddr { return _num2ip(_check_ipaddr( shift )) }

=head2 get_ksdevice

returns the ksdevice string for anaconda

=cut

sub get_ksdevice { return _check_ksdevice( shift ) }

=head2 get_lvm

returns the lvm option

=cut

sub get_lvm { return _check_lvm( shift ) }


=head2 get_macaddr($format)

returns the mac address as a string of the format specificed by I<$format>

I<$format> can be ieee, microsoft or basic. Basic is used if $format is
not present.

=cut

sub get_macaddr {

    my $self = shift;
    my $action = shift;
    $action ||= 'basic';

    my $mac = _check_macaddr($self);

    if ($action eq 'ieee') {
        $mac = $mac->as_ieee();
    } elsif ($action eq 'microsoft') {
        $mac = $mac->as_microsoft();
    } else {
        $mac = $mac->as_basic();
    }

    return $mac;

}

=head2 get_nameserver

returns the nameserver ip

=cut

sub get_nameserver { return _num2ip(_check_nameserver( shift )) }

=head2 get_netmask

returns the netmask ip

=cut

sub get_netmask { return _num2ip( _check_netmask( shift ) ) }

=head2 get_networkconfig

returns the networkconfig string for anaconda

=cut

sub get_networkconfig { return _check_networkconfig( shift ) }

=head2 get_pxefile

returns the pxe boot file name, as in the 'filename' field in dhcp

=cut

sub get_pxefile { return _check_pxefile( shift ) }

=head2 get_raid

returns the raid level as either noraid, raid0, raid1, raid5

=cut

sub get_raid { return _check_raid( shift ) }

=head2 get_ksdevice

returns the rescue string for anaconda

=cut

sub get_rescue { return _check_rescue( shift ) }

=head2 get_serialdevice

returns the serial device name

=cut

sub get_serialdevice { return _check_serialdevice( shift ) }

=head2 get_serialspeed

returns the speed of the serial device

=cut

sub get_serialspeed { return _check_serialspeed( shift ) }

=head2 get_swapsize

returns the swap size

=cut

sub get_swapsize { return _check_swapsize( shift ) }

=head2 get_syslogserver

returns the syslog server ip

=cut

sub get_syslogserver { return _num2ip(_check_syslogserver( shift )) }

=head2 get_yum_repos

returns the location of yum repos

=cut

sub get_yum_repos { return _check_yum_repos( shift ) }



=head1 INTERNAL FUNCTIONS

=head2 _init

Checks all the data, dies if anything is no good.

B<IF YOU REARRANGE THINGS - BE CAREFULL NOT TO CREATE LOOPS>

Some checks are cross dependant, which which means that the
order of these is quite important, the idea is to check the
basic items first then work up from there.

The basic items dont look outside themselves for data, more complex
checks do. This is where the risk of loops exists!

In other cases I have just elected an order which could be just as easily
and perhaps as validly done another way.

For example, should arch be checked, which then checks the chassis as
a dependancy, or should checking chassis result in arch being checked
as a dependancy?

Then consider that an OS must then also be compared against the chassis
and the arch.

Its not that important, as long as the arch is checked against the chassis
and is checked to work with the OS, but just keep that concept in mind
if you decide to rearrange things.



=cut

sub _init {

    my $self = shift;

    # these dont depend on anything
    _check_hostname($self);
    _check_ipaddr($self);
    _check_lvm($self);
    _check_macaddr($self);
    _check_nameserver($self);
    _check_netmask($self);
    _check_osver($self);
    _check_rescue($self);
    _check_syslogserver($self);
    _check_disk_extrapart($self);


    # these depend only on the above
    _check_bootfiles($self);
    _check_bootloader($self);
    _check_chassis($self);
    _check_gateway($self);
    _check_networkconfig($self);
    _check_yum_repos($self);


    # these depend only on the above
    _check_arch($self);
    _check_disk_type($self);
    _check_ksdevice($self);
    _check_serialdevice($self);
    _check_serialspeed($self);
    _check_swapsize($self);


    # these depend only on the above
    _check_bootloaderappend($self);
    _check_bootopt($self);
    _check_raid($self);


    # these depend only on the above
    _check_disk_layout($self);


    return

}

=head2 _check_arch

Checks that the arch is valid, returns the valid arch name.

Caches the final value so that subsequent calls are cheap

=cut

sub _check_arch {

    my $self = shift;

    # return the cached version if possible
    return $self->{_saved}->{arch}
        if $self->{_saved}->{arch};

    my $trans = $self->{trans};
    my $os_versions = $self->{os_versions};
    my $chassis_config = $self->{chassis_config};
    my $chassis = _check_chassis($self);

    my $osver = _check_osver($self);

    ## load arch or default to i386
    my $arch =
         $trans->param('arch')
      || $os_versions->{$osver}{defaults}{'arch'}
      || 'i386';

    ## check for arch compatibility with chassis
    if ( defined $chassis_config->{$chassis}{arch} ) {

        # normalise the available chassis in to an array
        my @chassi = ref $chassis_config->{$chassis}{arch} eq 'ARRAY'
                     ? @{ $chassis_config->{$chassis}{arch} }
                     : ( $chassis_config->{$chassis}{arch}) ;

            croak "Chassis doesnt support arch $arch"
                unless ( first { $_ eq $arch } @chassi );

    }

    ## check for arch compatibility with os
    if ( defined $os_versions->{$osver}{arch} ) {

        # normalise the available chassis in to an array
        my @os = ref $os_versions->{$osver}{arch} eq 'ARRAY'
                     ? @{ $os_versions->{$osver}{arch} }
                     : ( $os_versions->{$osver}{arch}) ;

            croak "Chassis doesnt support arch $arch"
                unless ( first { $_ eq $arch } @os );

    }

    return $self->{_saved}->{arch} = $arch

}

=head2 _check_bootfiles

=cut

sub _check_bootfiles {

    my $self = shift;

    # return the cached version if needed
    if ($self->{_saved}->{bootfiles} &&
            %{$self->{_saved}->{bootfiles}}) {
        return wantarray ? %{$self->{_saved}->{bootfiles}}
                         : $self->{_saved}->{bootfiles};
    };

    my $trans = $self->{trans};
    my $os_versions = $self->{os_versions};
    my $osver = _check_osver($self);

    my $bootfiles = $os_versions->{$osver}{bootfiles} || {};

    $self->{_saved}->{bootfiles} = $bootfiles;

    return wantarray ? %$bootfiles : $bootfiles;


}

=head2 _check_bootloader

Checks the boot loader is valid

=cut

sub _check_bootloader {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{bootloader}
        if $self->{_saved}->{bootloader};

    my $trans = $self->{trans};
    my $os_versions = $self->{os_versions};

    my $osver = _check_osver($self);

    ## determine bootloader
    my $bootloader = $trans->param('bootloader')
      || $os_versions->{$osver}{defaults}{bootloader}
      || 'lilo';

    ## check boot loader, this is crappy because its hard coded
    ## croak "Invalid bootloader ($bootloader)"
    ##    unless ( $bootloader =~ m/^(lilo|grub)$/ );

    ## check for bootloader os compatibility
    if ( defined $os_versions->{$osver}{bootloader} ) {

        # normalise the bootloader value in to an array
        my @bootloaders = ref $os_versions->{$osver}{bootloader} eq 'ARRAY'
                          ? @{ $os_versions->{$osver}{bootloader} }
                          : ($os_versions->{$osver}{bootloader});

        croak "Bootloader of $bootloader is no supported on this OS"
            unless ( first { $_ eq $bootloader } @bootloaders );

    }

    return $self->{_saved}->{bootloader} = $bootloader

}

=head2 _check_bootloaderappend

=cut

sub _check_bootloaderappend {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{bootloaderappend}
        if $self->{_saved}->{bootloaderappend};

    my $trans = $self->{trans};

    my @bootopt  = ( split /\s+/, $trans->param('bootopt') || q|| );

    my $chassis_config = $self->{chassis_config};
    my $chassis = _check_chassis($self);

    if ($chassis_config->{$chassis}{bootoptions}) {

          push @bootopt, ref $chassis_config->{$chassis}{bootoptions} eq 'ARRAY'
                         ? @{$chassis_config->{$chassis}{bootoptions}}
                         : ($chassis_config->{$chassis}{bootoptions});

    }

    my $serial  = _check_serialdevice($self);
    my $speed   = _check_serialspeed($self);

    if ($serial ne 'none') {
        push @bootopt, "console=${serial},${speed}n8";
    }

    return $self->{_saved}->{bootloaderappend} = join(' ', @bootopt)

}


=head2 _check_bootopt


=cut

sub _check_bootopt {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{bootopt}
        if $self->{_saved}->{bootopt};

    my $trans = $self->{trans};

    my @bootopt  = ( split /\s+/, $trans->param('bootopt') || q|| );

    my $chassis_config = $self->{chassis_config};
    my $chassis = _check_chassis($self);

    if ($chassis_config->{$chassis}{bootoptions}) {

          push @bootopt, ref $chassis_config->{$chassis}{bootoptions} eq 'ARRAY'
                         ? @{$chassis_config->{$chassis}{bootoptions}}
                         : ($chassis_config->{$chassis}{bootoptions});

    }

    my $serial  = _check_serialdevice($self);
    my $speed   = _check_serialspeed($self);

    if ($serial ne 'none') {
        push @bootopt, "console=${serial},${speed}n8";
    } else {
        push @bootopt,'text';
    }

    ## if this is a rescue boot, then set the boot option
    push @bootopt, qw/ rescue nomount shlisten=23 /
       if _check_rescue($self);

    return $self->{_saved}->{bootopt} = join(' ', @bootopt)

}

=head2 _check_chassis

Checks the current chassis

=cut

sub _check_chassis {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{chassis}
        if $self->{_saved}->{chassis};

    my $trans = $self->{trans};
    my $chassis_config = $self->{chassis_config};
    my $os_versions = $self->{os_versions};

    my $chassis = $trans->param('chassis')
        or croak q|Please select a chassis|;

    ## check that chassis is implemented
    croak qq|Chassis $chassis isnt supported by ts-kickstart|
        unless ( $chassis_config->{$chassis} );

    my $osver = _check_osver($self);

    # check that we arent trying to load a physical only OS into a virtual machine (ie kickstart ESX into a VM)
    croak qq|Cant load $osver into a virtual machine. Dont be silly.|
    if ( $chassis_config->{$chassis}{virtual}
        && $os_versions->{$osver}{'physical_only'} );

    return $self->{_saved}->{chassis} = $chassis

}

=head2 _check_disk_layout


=cut

sub _check_disk_layout {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{disk_layout}
        if $self->{_saved}->{disk_layout};

    my $disk_layout = 'noraid';

    my $trans = $self->{trans};
    my $chassis_config = $self->{chassis_config};
    my $chassis = _check_chassis($self);
    my $raid    = _check_raid($self);

    # vm's shouldnt use soft raid
    if ($chassis_config->{$chassis}{virtual}) {
        croak 'please dont use raid with virtualisation'
            if $raid ne 'noraid';
    }

    return $self->{_saved}->{disk_layout} = $raid || $disk_layout

}

=head2 _check_disk_extrapart

=cut

sub _check_disk_extrapart {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{disk_extrapart}
        if $self->{_saved}->{disk_extrapart};

    my @disk_extrapart;

    my $trans = $self->{trans};

    for my $extrapart ($trans->param('extrapart')) {

        my ( $mount, $size ) = split /=/, $extrapart
            or croak 'Malformed extrapart option';

        $mount = _stripspaces($mount);
        $size = _stripspaces($size);

        croak "extrapart disk size must be an integer, value for '$mount' was '$size'"
            if $size =~ m/\D/;

        # add a leading slash if absent
        $mount = "/$mount" if $mount !~ m|^/|;

        push @disk_extrapart, "$mount=$size";

    }

    return $self->{_saved}->{disk_extrapart} = join (',', @disk_extrapart)

}

=head2 _check_disk_type

=cut

sub _check_disk_type {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{disk_type}
        if $self->{_saved}->{disk_type};

    my $trans = $self->{trans};

    # TODO, we should care about disk OS compatibility
    # my $os_versions = $self->{os_versions};

    my $chassis_config = $self->{chassis_config};

    my $chassis = _check_chassis($self);
    my $disk_type  = $trans->param('disktype');

    ## check disk type
    if ( $disk_type && $chassis_config->{$chassis}{disktype} ) {

        my @disks = ref $chassis_config->{$chassis}{disktype} eq 'ARRAY'
                    ? @{ $chassis_config->{$chassis}{disktype} }
                    : ($chassis_config->{$chassis}{disktype});

        croak "This chassis ($chassis) doesnt support the requested disk type ($disk_type)"
            unless ( first { $disk_type eq $_ } @disks);

    ## go to default if unspecified
    } else {

        $disk_type = (ref $chassis_config->{$chassis}{disktype} eq 'ARRAY'
               ? $chassis_config->{$chassis}{disktype}[0]
               : $chassis_config->{$chassis}{disktype}) || 'ide';

    }

    return $self->{_saved}->{disk_type} = $disk_type

}

=head2 _check_gateway

=cut

sub _check_gateway {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{gateway}
        if $self->{_saved}->{gateway};

    my $ip = _check_ipaddr($self);
    my $netmask = _check_netmask($self);

    my $trans = $self->{trans};

    my $gateway = $trans->param('gateway')
        or croak q|Please provide a gateway|;

    $gateway = _ip2num(_valid_ip($gateway));

    croak q|Gateway is not in hosts subnet|
        if _mask_ip(_num2ip($gateway),_num2ip($netmask)) != _mask_ip(_num2ip($ip),_num2ip($netmask));



    return $self->{_saved}->{gateway} = $gateway

}

=head2 _check_hostname

Returns the hostname, does some checking, and caches.

=cut

sub _check_hostname {

my $self = shift;

    # return the cached version if possible
    return $self->{_saved}->{hostname}
        if $self->{_saved}->{hostname};

    my $trans = $self->{trans};

    my $hostname   = $trans->param('hostname')
        or croak 'Hostname not provided';

    ## check hostname
    $hostname = _stripspaces($hostname);

    croak "Invalid hostname parameter"
        unless ( $hostname =~ m/^([\w\.-]+)$/ );

    return $self->{_saved}->{hostname} = $hostname

}

=head2 _check_ipaddr

=cut

sub _check_ipaddr {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{ipaddr}
        if $self->{_saved}->{ipaddr};

    my $trans = $self->{trans};

    my $ipaddr = $trans->param('ipaddr')
        or croak "Please provide an ip address";

    $ipaddr = _ip2num(_valid_ip($ipaddr));

    return $self->{_saved}->{ipaddr} = $ipaddr

}


=head2 _check_ksdevice

=cut

sub _check_ksdevice {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{ksdevice}
        if $self->{_saved}->{ksdevice};

    my $trans = $self->{trans};
    my $chassis = _check_chassis($self);
    my $chassis_config = $self->{chassis_config};

    my $os_versions = $self->{os_versions};
    my $osver = _check_osver($self);

    ## load chassis
    my $ksdevice =
        $trans->param('ksdevice')
       || $os_versions->{$osver}{defaults}{ksdevice}
       || $chassis_config->{$chassis}{ksdevice}
       || 'eth0';

    # this needs to be re-examined for newer anaconda

    ## check eth device is something reasonable
    #croak "Invalid ksdevice ($ksdevice)"
    #    unless ( $ksdevice =~ /^eth\d+$/ );

    return $self->{_saved}->{ksdevice} = $ksdevice

}

=head2 _check_lvm

=cut

sub _check_lvm {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{lvm}
        if defined $self->{_saved}->{lvm};

    my $trans = $self->{trans};

    my $lvm   = $trans->param('lvm') || 'nolvm';

    return $self->{_saved}->{lvm} = $lvm;

}


=head2 _check_macaddr

Checks the mac address

=cut

sub _check_macaddr {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{macaddr}
        if $self->{_saved}->{macaddr};

    my $trans = $self->{trans};

    # this will croak if there is a problem, and we will let it pass through
    my $macaddr    = NetAddr::MAC->new($trans->param('macaddr'));

    return $self->{_saved}->{macaddr} = $macaddr

}

=head2 _check_nameserver

=cut

sub _check_nameserver {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{nameserver}
        if $self->{_saved}->{nameserver};

    my $trans = $self->{trans};

    my $nameserver = $trans->param('nameserver')
        || '10.10.10.10';

    $nameserver = _ip2num(_valid_ip($nameserver));

    return $self->{_saved}->{nameserver} = $nameserver

}


=head2 _check_netmask

=cut

sub _check_netmask {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{netmask}
        if $self->{_saved}->{netmask};

    my $trans = $self->{trans};

    my $netmask = $trans->param('netmask')
        || '255.255.255.0';

    $netmask = _ip2num(_valid_ip($netmask));

    return $self->{_saved}->{netmask} = $netmask

}

=head2 _check_networkconfig

=cut

sub _check_networkconfig {

    my $self = shift;

    # return the cached version if possible
    return $self->{_saved}->{networkconfig}
        if $self->{_saved}->{networkconfig};

    my $trans = $self->{trans};
    my $os_versions = $self->{os_versions};
    my $osver = _check_osver($self);

    my $nc = $os_versions->{$osver}{network_config}{static};

    return $self->{_saved}->{networkconfig} = $nc

}

=head2 _check_osver

Checks that the os is valid, returns the valid version name.

=cut

sub _check_osver {

    my $self = shift;

    # return the cached version if possible
    return $self->{_saved}->{osver}
        if $self->{_saved}->{osver};

    my $trans = $self->{trans};
    my $os_versions = $self->{os_versions};

    my $osver = $trans->param('osver')
                    || $trans->param('rhver');

    ## check for a an os version
    croak 'No osver (Operating System Version) supplied'
        unless $osver;

    ## check that the os version i supported
    croak "$osver is not supported by this KS server"
        unless $os_versions->{$osver};

    #~ ## check that there is a config file for that os
    #~ unless ( -r "/opt/trn/ts-kickstart/conf/$osver.conf" ) {
        #~ print $sock trans_data ERRMSG =>
          #~ "No sub $osver (Operating System Version) config - $osver config";
        #~ print $sock trans_end 10;
        #~ return;
    #~ }

    #~ ## try and load the osversion info
    #~ unless ( require "/opt/trn/ts-kickstart/conf/$osver.conf" ) {
        #~ print $sock trans_data ERRMSG =>
          #~ "Couldn't load $osver (Operating System Version) config: $!";
        #~ print $sock trans_end 102;
        #~ return;
    #~ }

    # cache the value, since we assume its now 100% safe

    return $self->{_saved}->{osver} = $osver

}

=head2 _check_pxefile

=cut

sub _check_pxefile {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{pxefile}
        if $self->{_saved}->{pxefile};

    my $trans      = $self->{trans};

    my $os_versions = $self->{os_versions};
    my $osver = _check_osver($self);

    my $pxefile = $os_versions->{$osver}{pxefile}
        or croak "pxefile missing for $osver";

    return $self->{_saved}->{pxefile} = $pxefile

}

=head2 _check_raid


=cut

sub _check_raid {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{raid}
        if exists $self->{_saved}->{raid};

    my $trans      = $self->{trans};
    my $raid       = $trans->param('raid')
                     || q|noraid|;

    my $disk_type = _check_disk_type($self);

    ## check raid configuration
    croak "Invalid raid configuration or level ($raid)"
        unless ( $raid =~ m/^raid[015]$|^noraid$/ );

    ## check raid sanity
    croak 'Invalid mix of hwraid and softraid.'
        if ( $disk_type eq 'hwraid' and $raid ne 'noraid');

    return $self->{_saved}->{raid} = $raid

}

=head2 _check_rescue

=cut

sub _check_rescue {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{rescue}
        if $self->{_saved}->{rescue};

    my $trans = $self->{trans};

    my $rescue       = $trans->param('rescue')       || 0;

    return $self->{_saved}->{rescue} = $rescue

}

=head2 _check_serialdevice

=cut

sub _check_serialdevice {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{serialdevice}
        if $self->{_saved}->{serialdevice};

    my $trans = $self->{trans};

    my $chassis_config = $self->{chassis_config};
    my $os_versions = $self->{os_versions};

    my $chassis = _check_chassis($self);
    my $osver = _check_osver($self);

    ## set serial output, default to com 1
    my $serialdevice = $trans->param('serial')
       || $chassis_config->{$chassis}{serial}
       || $os_versions->{$osver}{defaults}{serial}
       || 'ttyS0';

    # this is kind of crappy
    # croak "Invalid serial port ($serial)"
    #    unless ( $serialdevice =~ m/^(none|ttyS\d+)$/ );

    return $self->{_saved}->{serialdevice} = $serialdevice

}

=head2 _check_serialspeed

=cut

sub _check_serialspeed {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{serialspeed}
        if $self->{_saved}->{serialspeed};

    my $trans = $self->{trans};
    my $chassis_config = $self->{chassis_config};

    my $chassis = _check_chassis($self);

    ## set serious speed or default to 19200 (9600 is mainly for sun)
    my $serial_speed = $trans->param('serial_speed')
      || $chassis_config->{$chassis}{serial_speed}
      || '19200';

    return $self->{_saved}->{serialspeed} = $serial_speed

}

=head2 _check_syslogserver

=cut

sub _check_syslogserver {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{syslogserver}
        if $self->{_saved}->{syslogserver};

    my $trans = $self->{trans};

    my $syslogserver = $trans->param('syslogserver')
        || '10.10.10.10';

    $syslogserver = _ip2num(_valid_ip($syslogserver));

    return $self->{_saved}->{syslogserver} = $syslogserver

}

=head2 _check_swapsize

=cut

sub _check_swapsize {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{swapsize}
        if defined $self->{_saved}->{swapsize}; # 0 swap space is ok

    my $chassis_config = $self->{chassis_config};
    my $os_versions = $self->{os_versions};

    my $chassis = _check_chassis($self);
    my $osver = _check_osver($self);

    my $trans = $self->{trans};

    my $swapsize = $trans->param('swapsize');

    croak 'swapsize must be a number'
       if ($swapsize && $swapsize =~ m/\D/); # any non-number, decimals are also evil

    if (! defined $swapsize or $swapsize eq '') { # 0 swap space is ok
       $swapsize = $chassis_config->{$chassis}{swapsize}
       || $os_versions->{$osver}{defaults}{swapsize}
       || '1024';
    }

    return $self->{_saved}->{swapsize} = $swapsize

}

=head2 _check_yum_repos

Checks that the yum_repos is valid, returns the valid path.

Caches the final value so that subsequent calls are cheap

=cut

sub _check_yum_repos {

    my $self = shift;

    # return the cached version if needed
    return $self->{_saved}->{yum_repos}
        if $self->{_saved}->{yum_repos};

    my $trans = $self->{trans};
    my $os_versions = $self->{os_versions};

    my $osver = _check_osver($self);

    ## set the yum repos location
    my $yum_repos =
         $trans->param('yum_repos')
      || $os_versions->{$osver}{defaults}{yum_repos}
      || $YUM_REPOS;

    return $self->{_saved}->{yum_repos} = $yum_repos

}



=head1 INTERNAL UTILITIES

=head2 _stripspaces(I<$string>)

Removes leading and trailing white space, converts tabs to spaces and reduces
multiple spaces in to a single space.

Then returns the string.

=cut

sub _stripspaces {
    my $bla = shift;
    $bla =~ s/^\s+//;
    $bla =~ s/\s+$//;
    $bla =~ s/\t+/ /g;
    $bla =~ s/\s+/ /g;
    return $bla;
}

# this is stolen from http://cpansearch.perl.org/src/NEELY/Data-Validate-IP-0.11/lib/Data/Validate/IP.pm
# it should be factored out in to an OIE module of its own

## This next three functions should be refactored into another module.
## Note to self. Do that :)

sub _valid_ip {
    my $value = shift;

    return unless defined($value);
    my (@octets) = $value =~ m/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
    croak "Ip address $value is invalid"
        unless ( @octets == 4 );

    for (@octets) {

        croak "Ip address $value is invalid"
            unless ( $_ >= 0 && $_ <= 255 && $_ !~ m/^0\d{1,2}$/ );
    }

    return join( q{.}, @octets );
}

# stolen from http://cpansearch.perl.org/src/SARENNER/Net-IPAddress-1.10/IPAddress.pm

sub _ip2num {
    return ( unpack( 'N', pack( 'C4', split( m{\.}, $_[0] ) ) ) );
}

sub _num2ip {
    return ( join( q{.}, unpack( 'C4', pack( 'N', $_[0] ) ) ) );
}

sub _mask_ip {
    my ( $ipaddr, $mask ) = @_;
    my $addr = _ip2num(_valid_ip($ipaddr));

    if ( $mask !~ m/^\d\d$/ ) { # Mask can be sent as either "255.255.0.0" or "16"
        $mask = _ip2num($mask);
    }
    else {

        #$mask = ( ( ( 1 << $mask ) - 1 ) << ( 32 - $mask ) );
        #$mask = 2**32 - 2**(32-$mask);
        $mask = 4294967296 - 2**( 32 - $mask );
    }
    return $addr & $mask;
}

=head1 TODO

  Replace ip address validation with something not internally implemented

=head1 AUTHOR

Dean Hamstead C<< <dean@fragfest.com.au> >>

=cut

1;
