#!/usr/bin/perl

## Simple script that sends a daily report of mac addresses which are sending DHCPDISCOVER of DHCPREQUEST's
## I use this to check for chatter, which often indicates a bouncing machine or sometimes an out of band device making noise.
## This will also give you a list of mac addresses which were likely PXE-booted
## Obviously there is a lot of human interpretation needed for the report, nor would it be usefull on a busy dhcp server,
## we only use dhcp in our VLANs for kickstart installs so it works well enough

## You will need oui.txt from http://standards.ieee.org/develop/regauth/oui/oui.txt

use strict;
use warnings;
use List::Util qw(max first);
use Sys::Hostname;

my $syslog = q|/var/log/messages|;
my $defaultto = 'some@email.com';
my $mailer =
  first { -x $_ } qw(/usr/sbin/sendmail /usr/bin/sendmail /usr/lib/sendmail);
die "couldnt find a mailer" unless $mailer;

my $me = hostname();
my $from      = "autobuild\@$me";

my %oui;
my $ouifile = ( $ARGV[0] eq '-d' ) ? $ARGV[1] : $ARGV[0];
if ($ouifile && -f $ouifile) {
	open my $fh, '<', $ouifile
	    or die "failed to open $ouifile: $!";
	my @lines = grep {m/\(base 16\)/} <$fh>;
	close $fh;
	%oui = map {m/^(......)\s+\(base 16\)\s+(.+)\s*$/; uc($1),$2} @lines;
}
sub oui_vendor {
	my $mac = shift or return 'UNKNOWN';
	$mac =~ s/[^A-Fa-f0-9]//g; # remove non-hex
	$mac =~ s/^(......).*/$1/; # first 6 characters
        return $oui{uc($mac)} || 'UNKNOWN'
}

my %stats; # we collect the stats in this

open my $fh, '<',$syslog
        or die "failed to open $syslog: $!";

## suck the file and collect up the stats

my ($packet, $mac); # no sense in creating these over and over

for my $line (<$fh>) {

        next unless $line =~ m/dhcpd/;

        next unless ($packet, $mac) = $line =~ m/(DHCPDISCOVER|DHCPREQUEST).+([0-9A-f]{2}:[0-9A-f]{2}:[0-9A-f]{2}:[0-9A-f]{2}:[0-9A-f]{2}:[0-9A-f]{2})/;

        $stats{$mac}{$packet}++;

}

close $fh;

## now assemble the the report

my $csv  = "VENDOR, MAC, PACKET, COUNT\n";

# find the highest values, so they can be sorted on
my %done;
while (my ($key, $value) = each %stats) {
        $done{$key} = max values %$value;
}

for $mac (sort {$done{$b} <=> $done{$a}} keys %done) {

	my $vendor = oui_vendor($mac);

        for $packet (sort {$a cmp $b} keys %{$stats{$mac}}) {
                $csv .= "$vendor, $mac, $packet, ".$stats{$mac}{$packet}."\n";
        }

}


    my $message = <<EOF;
Hello,

I am a perl script called $0 running on $me

Here is my daily report for kickstart DHCP requests

$csv

--- END OF EMAIL ---
EOF


    if ( $ARGV[0] && $ARGV[0] eq '-d' ) {

        print "Email would be send to: $defaultto\n";
	print "Email would be sent from: $from\n";
	print "Email would be sent with: $mailer\n";
        print $message, "\n";

    }
    else {

        ### Open the command in a taint-safe fashion:
        my $pid = open my $SENDMAIL, '|-';
        defined($pid) or die "open of pipe failed: $!\n";
        if ( !$pid ) {    ### child
            exec( $mailer, '-t' ) or die "can't exec $mailer: $!\n";
            ### NOTREACHED as exec doesnt return
        }
        else {            ### parent

            print $SENDMAIL "From: $from\n";
            print $SENDMAIL "To: $defaultto\n";
            print $SENDMAIL "Subject: Autobuild daily report from $me\n";
            print $SENDMAIL "X-Script-Name: $0\n";

            print $SENDMAIL "\n", $message;
            close $SENDMAIL || die "error closing $mailer: $! (exit $?)\n";

        }

    }
1