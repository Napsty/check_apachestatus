#!/usr/bin/perl -w
####################### check_apachestatus.pl #######################
# Version : 1.5
# Date : Jul 7 2025
# Copyright 2007 De Bodt Lieven (Lieven.DeBodt at gmail.com)
# Copyright 2008 Karsten Behrens (karsten at behrens dot in)
# Copyright 2008 Geoff McQueen (geoff.mcqueen at hiivesystems dot com)
# Copyright 2025 Claudio Kuenzler (ck at claudiokuenzler dot com)
# Licence    : GPL - http://www.fsf.org/licenses/gpl.txt
#############################################################
# 20080912 <karsten at behrens dot in> v1.2
#          added output of Requests/sec, kB/sec, kB/request  
#          changed perfdata output so that PNP accepts it
#          http://www.behrens.in/download/check_apachestatus.pl.txt
#
# 20080930 <karsten at behrens dot in> v1.3
#          Fixed bug in perfdata regexp when Apache output was
#          "nnn B/sec" instead of "nnn kB/sec"
#
# 20081231 <geoff.mcqueen at hiivesystems dot com > v1.4
#          Made the scale logic more robust to byte only, kilobyte
#          and provided capacity for MB and GB scale options
#          on bytes per second and bytes per request (untested)
#
# 20250707 <ck at claudiokuenzler dot com > v1.5
#          Added optional parameter for setting user agent (-a / --agent)
#          Fixed uninitialized variable warnings
#          Fixed busy and idle worker parsing (used in plugin output)
#############################################################
# help : ./check_apachestatus.pl -h

use strict;
use Getopt::Long;
use LWP::UserAgent;
use Time::HiRes qw(gettimeofday tv_interval);

# Nagios specific
use lib "/usr/lib/nagios/plugins";
use utils qw(%ERRORS $TIMEOUT);
#my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);

# Globals
my $Version='1.5';
my $Name=$0;
my $o_host =		undef; 		# hostname 
my $o_help=		undef; 		# want some help ?
my $o_port = 		undef; 		# port
my $o_agent = 		undef; 		# user agent
my $o_version= 		undef;  	# print version
my $o_warn_level=	undef;  	# Number of available slots that will cause a warning
my $o_crit_level=	undef;  	# Number of available slots that will cause an error
my $o_timeout=  	15;            	# Default 15s Timeout
my $BusyWorkers=	0;
my $IdleWorkers=	0;

# functions
sub show_versioninfo { print "$Name version : $Version\n"; }

sub print_usage {
  print "Usage: $Name -H <host> [-p <port>] [-a <agent>] [-t <timeout>] [-w <warn_level> -c <crit_level>] [-V]\n";
}

# Get the alarm signal
$SIG{'ALRM'} = sub {
  print ("ERROR: Alarm signal (Nagios time-out)\n");
  exit $ERRORS{"CRITICAL"};
};

sub help {
  print "Apache Monitor for Nagios version ",$Version,"\n";
  print "GPL licence, (c)2006-2007 De Bodt Lieven\n\n";
  print_usage();
  print <<EOT;
-h, --help
   print this help message
-H, --hostname=HOST
   name or IP address of host to check
-p, --port=PORT
   Http port
-a, --agent=USERAGENT
   User-Agent to use in HTTP request
-t, --timeout=INTEGER
   timeout in seconds (Default: $o_timeout)
-w, --warn=MIN
   number of available slots that will cause a warning
   -1 for no warning
-c, --critical=MIN
   number of available slots that will cause an error
-V, --version
   prints version number
Note :
  The script will return
    * Without warn and critical options:
        OK       if we are able to connect to the apache server's status page,
        CRITICAL if we aren't able to connect to the apache server's status page,,
    * With warn and critical options:
        OK       if we are able to connect to the apache server's status page and #available slots > <warn_level>,
        WARNING  if we are able to connect to the apache server's status page and #available slots <= <warn_level>,
        CRITICAL if we are able to connect to the apache server's status page and #available slots <= <crit_level>,
        UNKNOWN  if we aren't able to connect to the apache server's status page

Perfdata legend:
"_;S;R;W;K;D;C;L;G;I;.;1;2;3"
_ : Waiting for Connection
S : Starting up
R : Reading Request
W : Sending Reply
K : Keepalive (read)
D : DNS Lookup
C : Closing connection
L : Logging
G : Gracefully finishing
I : Idle cleanup of worker
. : Open slot with no current process
1 : Requests per sec
2 : kB per sec
3 : kB per Request

EOT
}

sub check_options {
  Getopt::Long::Configure ("bundling");
  GetOptions(
      'h'     => \$o_help,        'help'          => \$o_help,
      'H:s'   => \$o_host,        'hostname:s'	  => \$o_host,
      'p:i'   => \$o_port,        'port:i'	  => \$o_port,
      'a:s'   => \$o_agent,       'agent:s'	  => \$o_agent,
      'V'     => \$o_version,     'version'       => \$o_version,
      'w:i'   => \$o_warn_level,  'warn:i'	  => \$o_warn_level,
      'c:i'   => \$o_crit_level,  'critical:i'	  => \$o_crit_level,
      't:i'   => \$o_timeout,     'timeout:i'     => \$o_timeout,

  );

  if (defined ($o_help)) { help(); exit $ERRORS{"UNKNOWN"}};
  if (defined($o_version)) { show_versioninfo(); exit $ERRORS{"UNKNOWN"}};
  if (((defined($o_warn_level) && !defined($o_crit_level)) || (!defined($o_warn_level) && defined($o_crit_level))) || ((defined($o_warn_level) && defined($o_crit_level)) && (($o_warn_level != -1) &&  ($o_warn_level <= $o_crit_level)))) { 
    print "Check warn and crit!\n"; print_usage(); exit $ERRORS{"UNKNOWN"}
  }
  # Check compulsory attributes
  if (!defined($o_host)) { print_usage(); exit $ERRORS{"UNKNOWN"}};
}

########## MAIN ##########
check_options();

my $ua = LWP::UserAgent->new( protocols_allowed => ['http'], timeout => $o_timeout);
$ua->agent($o_agent) if $o_agent;
my $timing0 = [gettimeofday];
my $response = undef;
if (!defined($o_port)) {
  $response = $ua->get('http://' . $o_host . '/server-status');
} else {
  $response = $ua->get('http://' . $o_host . ':' . $o_port . '/server-status');
}
my $timeelapsed = tv_interval ($timing0, [gettimeofday]);

my $webcontent = undef;
if ($response->is_success) {
  $webcontent=$response->content;
  my @webcontentarr = split("\n", $webcontent);
  my $i = 0;
  # Get the amount of idle and busy workers(Apache2)/servers(Apache1)
  while ($i < @webcontentarr) {
    if ($webcontentarr[$i] =~ /(\d+)\s+requests\s+currently\s+being\s+processed,.*\s+(\d+)\s+idle\s+workers/) {
      ($BusyWorkers, $IdleWorkers) = ($webcontentarr[$i] =~ /(\d+)\s+requests\s+currently\s+being\s+processed,.*\s+(\d+)\s+idle\s+workers/);
    }
    $i++;
  }

  # get requests/sec, kb/sec, kb/req
  $i = 0;
  my $ReqPerSec=undef;
  my $KbPerSec=undef;
  my $KbPerReq=undef;

  my $KbRatios = {
	g => 1048576,
	m => 1024,
	k => 1,
	empty => 0.0009765625,
  };

  while (($i < @webcontentarr) && ((!defined($ReqPerSec)) || (!defined($KbPerSec)) || (!defined($KbPerReq)))) {
    if ($webcontentarr[$i] =~ /([0-9]*\.?[0-9]+)\s+requests\/sec\s+-\s+([0-9]*\.?[0-9]+)\s+(\w)*B\/second\s+-\s+([0-9]*\.?[0-9]+)\s+(\w)*B\/request/) {
      my ($Requests, $bPerSec, $sPerSec, $bPerReq, $sPerReq) = ($webcontentarr[$i] =~ /([0-9]*\.?[0-9]+)\s+requests\/sec\s+-\s+([0-9]*\.?[0-9]+)\s+(\w)*B\/second\s+-\s+([0-9]*\.?[0-9]+)\s+(\w)*B\/request/);
      $ReqPerSec=$Requests;
      if ($sPerSec) {
        $KbPerSec = $bPerSec*$KbRatios->{lc($sPerSec)};
      } else {
        $KbPerSec = $bPerSec*$KbRatios->{empty};
      }
      if ($sPerReq) {
        $KbPerReq = $bPerReq*$KbRatios->{lc($sPerReq)};
      } else {
        $KbPerReq = $bPerReq*$KbRatios->{empty};
      }
    }
    $i++;
  }

  # Get the scoreboard
  my $ScoreBoard = "";
  $i = 0;
  my $PosPreBegin = undef;
  my $PosPreEnd = undef;
  while (($i < @webcontentarr) && ((!defined($PosPreBegin)) || (!defined($PosPreEnd)))) {
    if (!defined($PosPreBegin)) {
      if ( $webcontentarr[$i] =~ m/<pre>/i ) {
        $PosPreBegin = $i;
      }
    } 
    if (defined($PosPreBegin)) {
      if ( $webcontentarr[$i] =~ m/<\/pre>/i ) {
        $PosPreEnd = $i;
      }
    }
    $i++;
  }
  for ($i = $PosPreBegin; $i <= $PosPreEnd; $i++) {
    $ScoreBoard = $ScoreBoard . $webcontentarr[$i];
  }
  $ScoreBoard =~ s/^.*<[Pp][Rr][Ee]>//;
  $ScoreBoard =~ s/<\/[Pp][Rr][Ee].*>//;

  my $CountOpenSlots = ($ScoreBoard =~ tr/\.//);
  if (defined($o_crit_level) && ($o_crit_level != -1)) {
    if (($CountOpenSlots + $IdleWorkers) <= $o_crit_level) {
      printf("CRITICAL %f seconds response time. Idle %d, busy %d, open slots %d | 'Waiting for Connection'=%d 'Starting Up'=%d 'Reading Request'=%d 'Sending Reply'=%d 'Keepalive (read)'=%d 'DNS Lookup'=%d 'Closing Connection'=%d 'Logging'=%d 'Gracefully finishing'=%d 'Idle cleanup'=%d 'Open slot'=%d 'Requests/sec'=%0.1f 'kB per sec'=%0.1fKB 'kB per Request'=%0.1fKB\n", $timeelapsed, $IdleWorkers, $BusyWorkers, $CountOpenSlots, ($ScoreBoard =~ tr/\_//), ($ScoreBoard =~ tr/S//),($ScoreBoard =~ tr/R//),($ScoreBoard =~ tr/W//),($ScoreBoard =~ tr/K//),($ScoreBoard =~ tr/D//),($ScoreBoard =~ tr/C//),($ScoreBoard =~ tr/L//),($ScoreBoard =~ tr/G//),($ScoreBoard =~ tr/I//), $CountOpenSlots, $ReqPerSec, $KbPerSec, $KbPerReq);
      exit $ERRORS{"CRITICAL"}
    }
  } 
  if (defined($o_warn_level) && ($o_warn_level != -1)) {
    if (($CountOpenSlots + $IdleWorkers) <= $o_warn_level) {
      printf("WARNING %f seconds response time. Idle %d, busy %d, open slots %d | 'Waiting for Connection'=%d 'Starting Up'=%d 'Reading Request'=%d 'Sending Reply'=%d 'Keepalive (read)'=%d 'DNS Lookup'=%d 'Closing Connection'=%d 'Logging'=%d 'Gracefully finishing'=%d 'Idle cleanup'=%d 'Open slot'=%d 'Requests/sec'=%0.1f 'kB per sec'=%0.1fKB 'kB per Request'=%0.1fKB\n", $timeelapsed, $IdleWorkers, $BusyWorkers, $CountOpenSlots, ($ScoreBoard =~ tr/\_//), ($ScoreBoard =~ tr/S//),($ScoreBoard =~ tr/R//),($ScoreBoard =~ tr/W//),($ScoreBoard =~ tr/K//),($ScoreBoard =~ tr/D//),($ScoreBoard =~ tr/C//),($ScoreBoard =~ tr/L//),($ScoreBoard =~ tr/G//),($ScoreBoard =~ tr/I//), $CountOpenSlots, $ReqPerSec, $KbPerSec, $KbPerReq);
      exit $ERRORS{"WARNING"}
    }
  }
  printf("OK %f seconds response time. Idle %d, busy %d, open slots %d | 'Waiting for Connection'=%d 'Starting Up'=%d 'Reading Request'=%d 'Sending Reply'=%d 'Keepalive (read)'=%d 'DNS Lookup'=%d 'Closing Connection'=%d 'Logging'=%d 'Gracefully finishing'=%d 'Idle cleanup'=%d 'Open slot'=%d 'Requests/sec'=%0.1f 'kB per sec'=%0.1fKB 'kB per Request'=%0.1fKB\n", $timeelapsed, $IdleWorkers, $BusyWorkers, $CountOpenSlots, ($ScoreBoard =~ tr/\_//), ($ScoreBoard =~ tr/S//),($ScoreBoard =~ tr/R//),($ScoreBoard =~ tr/W//),($ScoreBoard =~ tr/K//),($ScoreBoard =~ tr/D//),($ScoreBoard =~ tr/C//),($ScoreBoard =~ tr/L//),($ScoreBoard =~ tr/G//),($ScoreBoard =~ tr/I//), $CountOpenSlots, $ReqPerSec, $KbPerSec, $KbPerReq);
      exit $ERRORS{"OK"}
}
else {
  if (defined($o_warn_level) || defined($o_crit_level)) {
    printf("UNKNOWN %s\n", $response->status_line);
    exit $ERRORS{"UNKNOWN"}
  } else {
    printf("CRITICAL %s\n", $response->status_line);
    exit $ERRORS{"CRITICAL"}
  }
}
