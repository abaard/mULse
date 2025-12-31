#!/usr/bin/env perl

# mULse -> macOS Unified Logging syslog extension
# (c) Anders Baardsgaard 2025, mULse(at)(lastname).priv.no
#
# This software comes with NO WARRANTIES!
    
#								report on WiFi comm. parms if:
%LQMlogging	= (
	Frequency	=>	300,				# target: log status every 300sec (=5min), unless "something happens", like:
	rssi		=>	"10:diff;snr<25",		#   - RSSI changes by >10dB, if also SNR<25dB; or
	noise		=>	 "7:diff",			#   - noise changes by >7dB; or
	snr		=>	 "8:diff",			#   - SNR changes by >8dB; or
	cca		=>	"40:above;self<.6",		#   - CCA is >40%, if also own contribution is <0.6 (60%) of that; or
	txRate		=>	"20:below!0",			#   - TXrate <20Mbps, but non-zero; or
	txFail		=>	 "3:pct:txFrames",		#   - ratio of txFail to txFrames is >3%; or
	txRetrans	=>	"35:pct+:txFrames;txFrames>50",	#   - ratio of txRetrans to (txFrames+txRetrans) is >35%, if also #txFrames>50 (10fps); or
	rxRate		=>	"25:below!0",			#   - RXrate <25Mbps, but non-zero; or
	rxRetryFrames	=>	"20:pct+:rxFrames;rxFrames>50",	#   - ratio of rxRetryFrames to rxFrames is >20%, if also #rxFrames>50 (10fps)
#	rxToss		=>	"25:pct:rxFrames",
);

($true,$false)	= (0==0,0==1);

$usage		= "usage: $0 [syslog=HOST]\n";
$version	= "beta";

@I_am		= split(/\//,$0);
$I_am		= $I_am[$#I_am];				if ($I_am =~ /^(\S+)\.pl-?(.*)$/o) {($I_am,$variety) = ($1,$2)}
%my		= (
	name	=> $I_am,
	path	=> join("/", @I_am[0 .. ($#I_am-1)]),
	variety	=> $variety,
	user	=> $ENV{USER},
	PID	=> $$,
);

($doDots,$showMath)	= ($true,$false);
%path		= (
	log		=> "/usr/bin/log",
	networksetup	=> "/usr/sbin/networksetup",
	ping		=> "/sbin/ping",
);

eval "\$CLIparm{$1}=\$2" while $ARGV[0] =~ /^([\w\[\]]+)=(.*)/ && shift;
die $usage if ($#ARGV >= 0);
foreach my $key (keys %CLIparm) {die $usage unless ($key eq "syslog")}

######################

# NB! macOS UL parameters are CASE SENSITIVE, unless tagged with a "[c]"

my $predicate = "--predicate '(eventMessage CONTAINS[c] \" LQM:\")'";		# localhost airportd[621]: (CoreWiFi) [com.apple.WiFiManager:] [corewifi] LQM: rssi= ...
$logStreamCmd	= "$path{log} stream $predicate --style syslog --debug";

######################

$RE_dotNUM	= '[\d\.]+';
$RE_hex		= '[\da-f]';

$PP0{ETHs}	=  $RE_hex.'{1,2}:'.$RE_hex.'{1,2}:'.$RE_hex.'{1,2}:'.$RE_hex.'{1,2}:'.$RE_hex.'{1,2}:'.$RE_hex.'{1,2}';
$PP0{IP4}	= '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}';

######################

sub networksetup {
  my ($parm, $trigger, $unTrigger, @regExp) = @_;
  my $triggered = !$trigger;
  my @retVal = ();
  open(NWSU, "$path{networksetup} $parm |") || warn "unable to open $path{networksetup} $parm: $!\n";
  while (<NWSU>) {
    if ($triggered) {
      if ($unTrigger && /$unTrigger/) {
        $triggered = $false;
      } else {
        foreach my $ix (0 .. $#regExp) {
          if (/$regExp[$ix]/) {$retVal[$ix] = $1}
      } }
    } elsif (/$trigger/) {
      $triggered = $true;
  } }
  close(NWSU);
  return(@retVal);
}

my ($n,@wifiInfo,%wifiInfo) = (0,(),());
foreach my $element ("device","MACaddr","hostname","IPaddr","mask","router","WiFiID","currSSID") {
  $wifiInfo[$n] = $element; $wifiInfo{$element} = $n; $n++;
}
sub getMyWifiInfo {
  my @select = @_;
  my ($HWport, $device, $MACaddr, $IPaddr, $mask, $router, $WiFiID, $currSSID, $hostname, %select);
  if ($#select < 0) {
    foreach my $element (keys %wifiInfo)	{$select{$element} = $true}
  } else {
    foreach my $element (@select)		{$select{$element} = $true}
  }
  ($HWport, $device)			= networksetup("-listnetworkserviceorder",	'\(\d+\)\s*Wi-Fi',	'^\s*$',	('Hardware Port:\s*([^,\)]+)', 'Device:\s*([^,\)]+)'));
  if ($select{MACaddr}) {
    ($MACaddr)				= networksetup("-listallhardwareports",		'Device:\s*'.$device,	'^\s*$',	('Ethernet Address:\s*('.$PP0{ETHs}.')'));
  }
  if ($select{IPaddr} || $select{mask} || $select{router} || $select{WiFiID}) {
    ($IPaddr, $mask, $router, $WiFiID)	= networksetup("-getinfo $HWport",		"",			"",		('IP address:\s*('.$PP0{IP4}.')', 'Subnet mask:\s*('.$PP0{IP4}.')', 'Router:\s*('.$PP0{IP4}.')', 'Wi-Fi ID:\s*('.$PP0{ETHs}.')'));
  }
  if ($select{currSSID}) {		# this stopped working in macOS 15 (Sequoia):
    ($currSSID)				= networksetup("-getairportnetwork $device",	"",			"",		('Current Wi-Fi Network:\s*(.*)'));
  }
  if ($select{hostname}) {
    ($hostname)				= networksetup("getcomputername",		"",			"",		('^(.+)$'));
  }
# Also: $path{networksetup} -listpreferredwirelessnetworks $hardwareport	==> list of known SSIDs (for this interface/$hardwareport?)
# when "private MAC addr" is active; if it's neither $MACaddress nor $WiFiID, will "$path{networksetup} -getmacaddress" reveal it?
  return($device,$MACaddr,$hostname,$IPaddr,$mask,$router,$WiFiID,$currSSID);
# hw info: "system_profiler SPHardwareDataType" / "sysctl machdep.cpu.brand_string" / "sysctl hw.memsize"
# SSIDs (but no BSSIDs): system_profiler SPAirPortDataType
}

###################### -- logging stuff

@syslogFac = ("kern", "user", "mail", "daemon", "auth", "syslog", "lpr", "news", "uucp", "cron", "authpriv", "ftp", "local0", "local1", "local2", "local3", "local4", "local5", "local6", "local7");
@syslogLvl = ("emerg", "alert", "crit", "err", "warn", "notice", "info", "debug");
foreach my $i (0 .. $#syslogFac) {$syslogFac{$syslogFac[$i]} = $i}
foreach my $i (0 .. $#syslogLvl) {$syslogLvl{$syslogLvl[$i]} = $i}

($facility,$level)	= ("user","info");

if ($doDots) {select((select(STDOUT), $|=1)[0])}	#	disable buffering ==> flush on write

if ($CLIparm{syslog}) {
  use Socket;     
  socket(S, PF_INET, SOCK_DGRAM, getprotobyname("udp"));
  bind(S, sockaddr_in(0, pack("C4",split(/\./, "0.0.0.0"))));
#
  my ($syslogSrv,$syslogPort) = ($CLIparm{syslog},getservbyname("syslog","udp"));
  if ($syslogSrv =~ /^([^:]+):(\d+)$/) {($syslogSrv,$syslogPort) = ($1,$2)}
  if ($syslogPort =~ /[a-z]/i) {$syslogPort = getservbyname($syslogPort,"udp")}
  my @dst = gethostbyname($syslogSrv);
  @dst = map { inet_ntoa($_) } @dst[4 .. $#dst];
  if ($#dst >= 0) {
    $syslogDst = sockaddr_in($syslogPort, pack("C4",split(/\./,$dst[0])));
    $syslogPrefix = "<" . ($syslogFac{$facility}*8+$syslogLvl{$level}) . ">";
  } else {
    warn "syslog host name doesn't resolve: $syslogSrv ?\n";
  }
}

sub logIt {
  my ($msg) = @_;
  if ($doDots) {print "\r"}
  print "$logTime $msg\n";
  if (defined($syslogDst)) {
    send(S, "${syslogPrefix}\[$my{name}\] $my{wifiMAC} $msg", 0, $syslogDst);
  }
}

######################

#-----------
# LQM: rssi=-50dBm per_ant_rssi=(-50dBm, -52dBm) noise=-100dBm snr=28 cca=8.0% ccaSelfTotal=0 ccaOtherTotal=0 interferenceTotal=0 txRate=173.3Mbps txFrames=30 txFail=0 txRetrans=1 txFallbackRate=86.7Mbps rxRate=173.3Mbps rxFrames=35 rxRetryFrames=9 rxToss=17 beaconRecv=48 beaconSched=48 txFwFrames=3 txFwFail=0 txFwRetrans=0

$LQMcount	= $LQMlastLogged= undef;
%LQMaggregate	= %LQMprevNum	= ();
$LQMaggrTags	= "ccaSelfTotal ccaOtherTotal interferenceTotal txFrames txFail txRetrans rxFrames rxRetryFrames rxToss beaconRecv beaconSched";	# +txFwFrames,txFwFail,txFwRetrans
$LQMignoreTags	= "per_ant_rssi txFwFrames txFwFail txFwRetrans";
$LQMdoLaterTags	= "txFallbackRate beaconRecv beaconSched";
$LQMccaPtTags	= "ccaSelfTotal ccaOtherTotal interferenceTotal";
foreach my $tag (split(/ /, $LQMaggrTags))	{$LQMaggr{$tag} = $true}
foreach my $tag (split(/ /, $LQMignoreTags))	{$LQMignore{$tag} = $true}
foreach my $tag (split(/ /, $LQMdoLaterTags))	{$LQMdoLater{$tag} = $true}
%LQMccaParts	= (
	"ccaSelfTotal"		=> "self",
	"ccaOtherTotal"		=> "other",
	"interferenceTotal"	=> "ifrence",
);

sub pct {
  my ($nom,$denom,$nDecimals) = @_;
  if (($denom == 0) || !defined($nom)) {
    return('?%');
  } else {
    my $pct = $nom * 100 / $denom;
    if (defined($nDecimals)) {
      $pct = int(.5+$pct*(10**$nDecimals))/(10**$nDecimals);
    }
    return("$pct\%");
  }
}

sub LQM {
  my ($data) = @_;
  my ($prefix,$output,$CCAparts) = ("","","");
  my ($now,$timeDiff) = (time(),"N/A ");

  sub LQMsummary {
    my $LQMsummary = "";
    foreach my $tag (@tagOrder) {
      next if ($LQMignore{$tag} || $LQMdoLater{$tag} || $LQMccaParts{$tag});			# TODO: LQM do Later
      if    ($LQMaggr{$tag})	{$LQMsummary .= "$tag=$LQMaggregate{$tag} "}
      elsif ($LQMnum{$tag})	{$LQMsummary .= "$tag=$LQMdata{$tag} "}
      else			{$LQMsummary .= "$tag=$LQMdata{$tag} "}
    }
    while ($LQMsummary =~ /\s$/o) {chop($LQMsummary)}
    return($LQMsummary);
  }

  if (defined($LQMlastLogged)) {$timeDiff = $now-$LQMlastLogged}
  $LQMcount++;
  my $doLog = 0;
  if ($timeDiff >= $LQMlogging{Frequency}) {$doLog++}
  %LQMdata = %LQMinfo = ();
  @tagOrder = ();
  while ($data =~ /^([^=]+)=(\([^\)]*\)|\S+) *(.*)$/o) {					# e.g: rssi=-54dBm per_ant_rssi=(-55dBm, -56dBm) noise=-97dBm snr=30 cca=4.0% (etc)
    my ($tag,$value) = ($1,$2);
    $data = $3;
    $LQMdata{$tag} = $value;
    push(@tagOrder, $tag);
    if ($LQMignore{$tag} || $LQMdoLater{$tag}) {						# TODO: LQM do Later
      next;
    } elsif ($LQMaggr{$tag}) {
      $LQMaggregate{$tag} += $value;
      $LQMnum{$tag} = $value;
    } else {
      if ($value =~ /^(-?[\d\.]+)(dBm|Mbps|\%)?$/o) {$LQMnum{$tag} = $1}
    }
    if ($LQMccaParts{$tag}) {
      $CCAparts .= "$LQMccaParts{$tag}=$LQMnum{$tag} ";
    }
  }
  while ($data =~ /^(\S+) = (\S+) *(.*)$/o) {							# e.g: network = <redacted> bssid = <redacted> channel = 40 BW = 20
    my ($tag,$value) = ($1,$2);
    $data = $3;
    $LQMinfo{$tag} = $value;
  }

  foreach my $tag (keys %LQMnum) {								# does any parameter exceed the boundary in "%LQMlogging = ( ... );" at top of file? ==> doLog++
    if ($LQMlogging{$tag}) {
      if ($LQMlogging{$tag} =~ /^(\d+):diff(;(\w+)([<>])(-?\d+))?$/o) {
        if ($2) {
          if (($4 eq ">") && ($LQMnum{$3} <= $5)) {next}
          if (($4 eq "<") && ($LQMnum{$3} >= $5)) {next}
        }
        if    (defined($LQMprevNum{$tag}) && (abs($LQMnum{$tag}-$LQMprevNum{$tag}) >= $1))	{$doLog++; my $expr = (($showMath) ? "\|$LQMnum{$tag}-$LQMprevNum{$tag}\|>=$1" : abs($LQMnum{$tag}-$LQMprevNum{$tag}));
												 $prefix .= "\[$tag: $expr" . (($tag eq "cca") ? "; LQMCCAPARTS" : "") . '] '}
      } elsif ($LQMlogging{$tag} =~ /^(\d+):above(;self<([\.\d]+))?$/o) {
        if ($LQMnum{$tag} >= $1) {
          if ($2 && ($tag eq "cca") && (($LQMnum{"ccaSelfTotal"}/$LQMnum{"cca"}) <= $3))	{$doLog++; my $expr = (($showMath) ? "$LQMnum{$tag}>=$1" : $LQMnum{$tag});
												 $prefix .= "\[$tag: $expr" . (($tag eq "cca") ? "; LQMCCAPARTS" : "") . '] '}
          elsif (!$2)										{$doLog++; my $expr = (($showMath) ? "$LQMnum{$tag}>=$1" : $LQMnum{$tag});
												 $prefix .= "\[$tag: $expr" . (($tag eq "cca") ? "; LQMCCAPARTS" : "") . '] '}
        }
      } elsif ($LQMlogging{$tag} =~ /^(\d+):below(\!(\d+))?$/o) {
        if ((!defined($3) || ($LQMnum{$tag} != $3)) && ($LQMnum{$tag} <= $1))			{$doLog++; my $expr = (($showMath) ? "$LQMnum{$tag}<=$1" : $LQMnum{$tag});
												 $prefix .= "\[$tag: $expr" . (($tag eq "cca") ? "; LQMCCAPARTS" : "") . '] '}
      } elsif ($LQMlogging{$tag} =~ /^(\d+):pct:(\w+)(;(\w+)([<>])(-?\d+))?$/o) {
        if ($3) {
          if (($5 eq ">") && ($LQMnum{$4} <= $6)) {next}
          if (($5 eq "<") && ($LQMnum{$4} >= $6)) {next}
        }
        if (($LQMnum{$2} > 0) && (($LQMnum{$tag}*100/$LQMnum{$2})>=$1))				{$doLog++; my $expr = (($showMath) ? "$LQMnum{$tag}*100/$LQMnum{$2}>=$1" : pct($LQMnum{$tag},$LQMnum{$2},0));
												 $prefix .= "\[$tag: $expr" . (($tag eq "cca") ? "; LQMCCAPARTS" : "") . '] '}
      } elsif ($LQMlogging{$tag} =~ /^(\d+):pct\+:(\w+)(;(\w+)([<>])(-?\d+))?$/o) {
        if ($3 && ($LQMnum{$4} <= $6)) {next}
        if ($3) {
          if (($5 eq ">") && ($LQMnum{$4} <= $6)) {next}
          if (($5 eq "<") && ($LQMnum{$4} >= $6)) {next}
        }
        if (($LQMnum{$2} > 0) && (($LQMnum{$tag}*100/($LQMnum{$2}+$LQMnum{$tag}))>=$1))		{$doLog++; my $expr = (($showMath) ? "$LQMnum{$tag}*100/($LQMnum{$2}+$LQMnum{$tag})>=$1" : pct($LQMnum{$tag},$LQMnum{$2}+$LQMnum{$tag},0));
												 $prefix .= "\[$tag: $expr" . (($tag eq "cca") ? "; LQMCCAPARTS" : "") . '] '}
  } } }
  foreach my $tag (keys %LQMinfo) {
    if (defined($LQMprevInfo{$tag}) && ($LQMinfo{$tag} ne $LQMprevInfo{$tag})) {
      $doLog++;
      $prefix .= "\[$tag: $LQMprevInfo{$tag}->$LQMinfo{$tag}\] ";
  } }


  if ($doLog > 0) {
    chop($CCAparts);
    $prefix =~ s/LQMCCAPARTS/$CCAparts/g;
    $output = LQMsummary();
    while ($prefix =~ /\s$/o) {chop($prefix)}
    logIt("\[dT=${timeDiff}s\] " . (($prefix) ? "$prefix " : "") . $output);
    %LQMaggregate = ();
    $LQMlastLogged = $now;
  } elsif ($LQMcount == 1) {
    logIt("LQM: " . LQMsummary());
  } elsif ($doDots) {
    print ".";
  }
  %LQMprevNum = %LQMnum;
  %LQMprevInfo = %LQMinfo;
  if (!defined($LQMlastLogged)) {$LQMlastLogged = time()}
}

######################

sub reg {
  my ($msg) = @_;
  return() if ($msg !~ /[A-Za-z]/);
  my @data = (split(/\s+/,$msg,2));
  if     ($data[0] eq  "LQM:")						{LQM($data[1])}
  if    ($data[0] =~ /^$RE_dotNUM$/)	{$data[0] = "(dotNUM)"}
  elsif ($data[0] =~ /^0x$RE_hex{9}$/)	{$data[0] = "hex{9}"}
}

######################

@myWifiInfo = getMyWifiInfo();
($my{wifiIntf},$my{wifiMAC},$my{hostname},$my{IPaddr},$my{mask},$my{router},$my{WiFiID},$my{currSSID}) = @myWifiInfo;

  open(INPUT, "$logStreamCmd |") || die "unable to run command; $!\n-->\t$logStreamCmd\n";
  print "$my{name} v-$version; " . localtime(time()) . "; cmd=$logStreamCmd;\n";
  print "".join(" # ", @myWifiInfo)."\n";
  $inputSrc = "CMD";

logIt("HELLO from $my{name} (" . (($my{variety})?$my{variety}:$version) . ") \@$my{hostname} " . (($my{currSSID})?"assocTo=$my{currSSID} ":"") . "IP=$my{IPaddr}/$my{mask}; PID=$my{PID}, user=$my{user}");

LINE:
while (<INPUT>) {
  $logEntryNo++;
  chomp();
# Case: "--style syslog"
  if (/^(\d{4}-\d{2}-\d{2}) ((\d{2}:\d{2}:\d{2})\.\d+)\S*\s+(\S+) ([^\[]+)\[\d+\]: (\(([^\)]+)\) )?(\[([^\]:]+):?([^\]]*)\] )?(\[([^\]]+)\] )?(<([^\[]+)\[\d+\]> )?\s*(.*)$/) {
    ($logDate,$logTime,$logHMS) = ($1,$2,$3);
    ($process,$sender,$subsystem,$subsubsys,$whatsThis,$realMsg) = ($5,$7,$9,$10,$12,$15);
    next if ($realMsg =~ /^\s*$/);
    reg($realMsg);
# Case: "--style compact"
  } elsif (/^(\d{4}-\d{2}-\d{2}) ((\d{2}:\d{2}:\d{2})\.\d{3}) (D[fb]|[IEA])(( +\w+)+?)\[\d+:$RE_hex+\] (\[([^\]]+)\]( \[([^\]]+)\]|(( \w+)+?): <(\w+)\[\d+\]>( [-\+]\[([^\]]+)\]([\w_]*:( \[$PP0{UUID}\])?)?)?)?|\(([^\)]+)\))?( -\[([^\]]+)\])?\s*(.*)$/o) {
#            1                   23                           4            56                         #1  2         3   4          56           7            8        9         A       B                          C           D    E             F      
#                              1                    3       2             4       6  5                #          2             4         6  5       7                        9                          B A 8 3           C  1             E  D      F
    ($logDate,$logTime,$logHMS) = ($1,$2,$3);
    ($process,$subsystem,$category,$realMsg) = ($5,$8,$18,$21);
    next if ($realMsg =~ /^\s*$/);
    if ($process =~/^\s+(.+)$/) {$process = $1}
    reg($realMsg);
# Case: input doesn't match...
  } else {
  }
}
close(INPUT);

__END__

