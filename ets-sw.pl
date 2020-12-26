#!/usr/bin/perl
##############################################################################
#
#  ETS-SW -- Wolfenstein: Enemy Territory Server Watch (remote)
#  (c) Vladi Shabanski <cade@bis.bg> 2003-2005
#  http://cade.datamax.bg/away/ets
#
#  Developed for play.evrocom.net server ET community
#  http://play.evrocom.net
#
#  This software is distributed under GPL license, see COPYING for details.
#
#  $Id: ets-sw.pl,v 1.2 2005/06/19 20:21:30 cade Exp $
#
##############################################################################
use FindBin;
use lib $ENV{ 'ETS_LIB' } || "$FindBin::Bin/ets_lib";
use Data::Dumper;
use ets;
use IO::Socket::INET;
use IO::Select;
use IO::File;
use Storable;
#use File::Tail;
use Fcntl;
use strict;

$| = 1;

our $DB_FILE      = $ENV{ 'ETS_DB_FILE_SW' } || 'ets-sw.db';  # bind address of the host machine

our $HERE         = $ENV{ 'IMPOSTOR_HERE' } || $ENV{ 'ETS_HERE' } || '127.0.0.1';  # bind address of the host machine
our $SERVERS      = $ENV{ 'ETS_SERVERS' };
our $O_LOOP_TIME  = $ENV{ 'ETS_O_LOOP_TIME' } || 60; # 1 minute default
our $SEEN_FILE    = $ENV{ 'ETS_SEEN_FILE' };
our $XPWINS_DIFF  = $ENV{ 'ETS_XPWINS_DIFF' } || 20; # minimum difference for xp wins theory calculation
our $PL_DIFF      = $ENV{ 'ETS_PL_DIFF' } || 2; # minimum team players count difference
our $PAGE_NAME    = $ENV{ 'ETS_PAGE_NAME' } || 'servers_watch';
our $SCREENSHOTS  = $ENV{ 'ETS_SCREENSHOTS' } || '#../../screenshots';

#$SERVER_IP = "203.22.13.13:27960";
#$SERVER_IP = "play.evrocom.net:27960";
#my @data = split /\n+/, rcon('!getstatus');
#my %data = split( /\\/, '.\.' . shift @data );
#print Dumper( \%data, \@data );
#sleep(2);
#print Dumper( rcon('!statusResponse') );
#exit;

### main() here ##############################################################

$TRANSLATION = load_hash( $ENV{'ETS_TRANSLATION'} ) || {};

$REVISION = '$Revision: 1.2 $';
$ETS_VER = $1 if $REVISION =~ /([\d\.]+)/;
$CREDITS = "<small><a href=http://cade.datamax.bg/away/ets><b>ETS-SW $ETS_VER</b></a> by 2003-2005 (c) <a href=mailto:cade\@bis.bg>&lt;cade\@bis.bg&gt;</a></small>";

# vars -----------------------------------------------------------------------

our $O_EXEC_TIME;
our $O_LAST_MAP;
our $O_LAST_TIME;
our $O_LAST_OK;

# main -----------------------------------------------------------------------

our %store;

our $SERVER_IP;  # used by rcon
our $SERVER_PWD; # used by rcon

my $store = retrieve( $DB_FILE ) if -e $DB_FILE;
%store = %$store if $store;

my $text;

for my $ip ( split /\s+/, $SERVERS )
  {
  $SERVER_IP  = $ip;
  $SERVER_IP .= ":27960" unless $SERVER_IP =~ /:\d+$/;

  DEBUG("query server $SERVER_IP\n");
  
  $O_EXEC_TIME  = $store{ $SERVER_IP }{ O_EXEC_TIME };
  $O_LAST_MAP   = $store{ $SERVER_IP }{ O_LAST_MAP  };
  $O_LAST_TIME  = $store{ $SERVER_IP }{ O_LAST_TIME };
  $O_LAST_OK    = $store{ $SERVER_IP }{ O_LAST_OK   };

  $text .= online_status();
  $text .= "<p><hr noshade><p>";
  
  $store{ $SERVER_IP }{ O_EXEC_TIME } = $O_EXEC_TIME;
  $store{ $SERVER_IP }{ O_LAST_MAP  } = $O_LAST_MAP ;
  $store{ $SERVER_IP }{ O_LAST_TIME } = $O_LAST_TIME;
  $store{ $SERVER_IP }{ O_LAST_OK   } = $O_LAST_OK  ;
  
  DEBUG("done server $SERVER_IP\n");
  }

$ENV{ 'REFRESH' } = "<meta http-equiv=refresh content=$O_LOOP_TIME>";
html_save( $PAGE_NAME, $text  );
delete $ENV{ 'REFRESH' };                     

store( \%store, $DB_FILE );

### ONLINE STATUS ###########################################################

sub online_status
{
  return if $O_LAST_OK and $O_EXEC_TIME > time();
  
  my $rcon = rcon('!getstatus');
  $O_LAST_OK = $rcon ? 1 : 0;
  return unless $O_LAST_OK;
  
  $O_EXEC_TIME = time() + $O_LOOP_TIME;

  my @srv = split /\n+/, $rcon;
  my %srv = split( /\\/, '.\.' . shift @srv );

  # players -----------------------------------------------------
  
  my @pdata;

  my %side;
  
  if( $srv{ 'Players_Allies' } and  $srv{ 'Players_Axis'   } )
    {
    $side{ $_ } = 'Ally' for split /\s+/, $srv{ 'Players_Allies' };
    $side{ $_ } = 'Axis' for split /\s+/, $srv{ 'Players_Axis'   };
    }
  elsif( $srv{ 'P' } )
    {
    my $c = 0;
    $_ > 0 ? $side{ $c++ } = ( '????','Axis','Ally','Spct' )[$_] : next for split //, $srv{ 'P' };
    }
  
  my %pl = ( 'Ally' => [], 'Axis' => [], 'Spct' => [] );

  my %xp;
  my $c = 0;
  for( @srv )
    {
    chomp();
    next unless /\S/;
    my ( $xp, $ping, $name ) = split /\s+/, $_, 3;
    $name =~ s/"//g; # "
    my $s = $side{ $c } || 'Spct';
    $xp{ $s } += $xp;
    push @{ $pl{ $s } }, [ substr( $name, 0, 30 ), $xp, $ping  ];
    $c++;
    }

  #for my $s ( ( 'Axis', 'Ally', 'Spct' ) )
  #  {
  #  @{ $pl{ $s } } = reverse sort @{ $pl{ $s } };
  #  }

  push @pdata, [ 'HEAD', '[<23%]Axis',       '[>5%]XP', '[>5%]Ping', 
                         '[<23%]Allies',     '[>5%]XP', '[>5%]Ping', 
                         '[<24%]Spectators', '[>5%]XP', '[>5%]Ping', ];
  #print Dumper( \%pl );
  while(4)
    {
    my @line;
    my $c;
    for my $s ( ( 'Axis', 'Ally', 'Spct' ) )
      {
      my $ar = shift( @{ $pl{ $s } } );
      #print Dumper( $pl{ $s });
      push @line, $ar ? @$ar : ( '', '', '' );
      $c++ if $ar;
      }
    last unless $c;
    push @pdata, [ '', @line ];
    }
  push @pdata, [ 'FOOT', '', '(SUM)', '', 
                         '', '(SUM)', '',
                         '', '(SUM)', '', ];

  if( $PL_DIFF > 0 )
    {
    my $pd = abs( @{ $pl{ 'Axis' } } - @{ $pl{ 'Ally' } } );
    et_print( 'PL_NOBALANCE', DIFF => $pd ) if $pd >= $PL_DIFF;
    }

  # server data -------------------------------------------------

  my $map = $srv{ 'mapname' };
  if( $O_LAST_MAP ne $map )
    {
    $O_LAST_MAP = $map;
    $O_LAST_TIME = time();
    }

  my $eta = 'unknown';
  if( $O_LAST_TIME )
    {
    $eta = int( $srv{'timelimit'} - ( time() - $O_LAST_TIME )/60 );
    $eta = "overtime/unknown" if $eta < 0;
    }

  my $gt = $srv{ 'g_gametype' };
  my $gts = 'unknown';
  $gts = 'Campaign' if $gt == 4;
  $gts = 'Stopwatch' if $gt == 3;
  $gts = 'Last Man Standing' if $gt == 5;
  $gts = 'Single Map Objective' if $gt == 2;

  my $winner = 'unknown';
  my $axp = $xp{ 'Axis' };
  my $ixp = $xp{ 'Ally' };
  my $max = $axp > $ixp ? $axp : $ixp;
  my $dif = $max > 0 ? ( 100 * abs( $axp - $ixp ) ) / $max : 0;
  if( $dif > $XPWINS_DIFF )
    {
    $winner = 'Axis'   if $axp > $ixp;
    $winner = 'Allies' if $axp < $ixp;
    # et_print( 'XP_NOBALANCE', DIFF => sprintf( "%.2f", $dif ), DES => "$axp:$ixp" );
    };
  $dif = sprintf "%.2f", $dif;  

  my $url = $srv{'URL'};
  
  my @data;
  push @data, [ 'HEAD', '[>50%]Name', '[<50%]Value' ];
  push @data, [ '', 'Host name',       $srv{'sv_hostname'} ];
  push @data, [ '', 'IP Address',      $SERVER_IP ];
  push @data, [ '', 'Version',         $srv{'version'} ];
  push @data, [ '', 'Game name (mod)', $srv{'gamename'} ];
  push @data, [ '', 'URL',             "<a href='$url'>$url</a>" ] if $url;
  push @data, [ '', 'Map',             $srv{'mapname'} ];
  push @data, [ '', 'Game type',       $gts ];
  push @data, [ '', 'Timelimit',       $srv{'timelimit'} . " min" ];
  push @data, [ '', 'Map started at',  scalar(localtime($O_LAST_TIME)) ];
  push @data, [ '', 'Finish ETA in',   "$eta min" ];
  push @data, [ '', 'XP Difference',   "$dif%" ];
  push @data, [ '', 'Probable winner', $winner ];
  
  my $text;

  my $scr = next_screen( $map );
  $text .= html_table( \@data );

  $text = make_columns( "<img src=$SCREENSHOTS/$scr width=400 height=300>", $text ) .
                         "<br>" .
                         html_table( \@pdata );
  return $text;
}

our @SCREENS;

sub next_screen
{
  my $map = shift;
  
  if( ! @SCREENS )
    {
    @SCREENS = glob "$OUTPUT_DIR/screenshots/*.jpg";
    s/^(.+?)([^\/]+)$/$2/ for @SCREENS;
    }
  
  my $border = $SCREENS[-1];
  while(4)
    {
    my $q = shift @SCREENS;
    push @SCREENS, $q;
    return $q if $q =~ /\Q$map\E/i;
    last if $q eq $border;
    }
  return 'no-screenshot.jpg';  
}

### UTILITIES ###############################################################

our %FILE_MT;
sub file_changed
{
  my $f  = shift;
  my $mt = (stat($f))[9];
  my $ch = $FILE_MT{ $f } != $mt;
  $FILE_MT{ $f } = $mt;
  return $ch;
}

sub rcon
{
  my $command = shift;
  
  DEBUG( "RCON DUMMY: $command" );
  
  my $sock = IO::Socket::INET->new( PeerAddr  => $SERVER_IP,
                                    Proto     => 'udp' ) or 
  die( "ERROR: cannot connect $SERVER_IP" );
      
  my $sel = IO::Select->new();
  $sel->add($sock);
  
  DEBUG( "status: rcon <<< $command" );
  if( $command =~ /^!(.*)/ )
    {
    #getinfo
    #getstatus
    $sock->send( "\xff\xff\xff\xff$1\n" );
    }
  else
    {  
    $sock->send( "\xff\xff\xff\xffrcon $SERVER_PWD $command" );
    }
  my $data;
  while( my @ready = $sel->can_read( 5 ) )
    {
    $sock->recv( $_, 4096 );
    s/\xff+(.*?)\n//;
    $data .= $_;
    };
  $data =~ s/\^.//g;
  
  my @data = split /\n+/, $data;
  my $data1 = $data[0];
  $data1 .= "..." if @data > 1;
  DEBUG( "status: rcon >>> $data1" );
  return $data;
}

sub logger
{
  my $msg = shift;
  my $tm = scalar localtime();
  print STDERR "[$tm] $msg\n";
  exit(1) if $msg =~ /^FATAL:/;
}

### RCON FUNCS ##############################################################

sub rcon_pb_sv_plist
{
  my %data;
  my @rcon = split /\n/, rcon( "pb_sv_plist" );
  for( @rcon )
    {
    logger("DEBUUUUG: $_\n");
    s/^PunkBuster Server:\s*//;
    next if /^(End of )?Player List/;
    my @pb = split /\s+/, $_, 9;
    # 0 [1]
    # 1 [f112ad6c41a48ada6b4cfc2e76fac9c1(?)]
    # 2 [193.200.15.141:29111]
    # 3 [OK]
    # 4 [1]
    # 5 [0.0]
    # 6 [0]
    # 7 [(W)]
    # 8 [[ZaZ]KserkS]
    $pb[1] = uc $pb[1];
    $pb[1] =~ s/\((.*?)\)$//;
    $_ = $1;
    my $age = $1 if /VALID:(\d+)/i;
    $pb[2] =~ s/:\d*$//;
    $pb[8] =~ s/\^.//g;
    
    $data{ $pb[8] }{ 'SLOT'   } = $pb[0];
    $data{ $pb[8] }{ 'GUID'   } = $pb[1];
    $data{ $pb[8] }{ 'AGE'    } = $age;
    $data{ $pb[8] }{ 'IP'     } = $pb[2];
    $data{ $pb[8] }{ 'STATUS' } = $pb[3];
    $data{ $pb[8] }{ 'POWER'  } = $pb[4];
    $data{ $pb[8] }{ 'RATE'   } = $pb[5];
    $data{ $pb[8] }{ 'SS'     } = $pb[6];
    $data{ $pb[8] }{ 'OS'     } = $pb[7];
    $data{ $pb[8] }{ 'NICK'   } = $pb[8];
    }
  # DEBUG( Dumper( \%data ) );
  return \%data;  
}

sub rcon_status
{
  my %data;
  my @rcon = split /\n/, rcon( "status" );
  for( @rcon )
    {
    next if /^map|^num|^---/;
    s/^\s+//;
    s/\s+$//;
    my @st = split /\s+/, $_, 8;
    # 0 [0] slot
    # 1 [973] xp  
    # 2 [11] ping
    # 3 [PlayerName] 
    # 4 [100] lastmsg
    # 5 [212.104.105.132:27960] 
    # 6 [60086] qport
    # 7 [4000] rate

    $st[3] =~ s/\^.//g;
    
    $data{ $st[3] }{ 'SLOT'   } = $st[0];
    $data{ $st[3] }{ 'XP'     } = $st[1];
    $data{ $st[3] }{ 'PING'   } = $st[2];
    $data{ $st[3] }{ 'LMSG'   } = $st[4];
    $data{ $st[3] }{ 'IP'     } = $st[5];
    $data{ $st[3] }{ 'QPORT'  } = $st[6];
    $data{ $st[3] }{ 'RATE'   } = $st[7];
    }
  # DEBUG( Dumper( \%data ) );
  return \%data;  
}

#############################################################################

=pod

$VAR1 = {
          'protocol' => '83',
          'sv_maxRate' => '25000',
          'g_minGameClients' => '8',
          'sv_allowAnonymous' => '0',
          'mapname' => 'raiders_b2',
          'g_axismaxlives' => '0',
          'g_needpass' => '0',
          'sv_hostname' => 'play.evrocom.net',
          'URL' => 'http://play.evrocom.net/',
          'sv_punkbuster' => '1',
          'g_alliedmaxlives' => '0',
          'mod_version' => '3.0.13',
          'g_balancedteams' => '1',
          'g_antilag' => '1',
          'g_maxlivesRespawnPenalty' => '0',
          'g_medicChargeTime' => '45000',
          'sv_floodProtect' => '0',
          'g_engineerChargeTime' => '30000',
          'g_friendlyFire' => '1',
          'g_bluelimbotime' => '15000',
          'g_redlimbotime' => '25000',
          'g_soldierChargeTime' => '20000',
          'g_maxGameClients' => '0',
          'sv_privateClients' => '0',
          'timelimit' => '30',
          'g_covertopsChargeTime' => '30000',
          'g_voteFlags' => '0',
          'sv_maxPing' => '200',
          'sv_minguidage' => '0',
          'g_maxlives' => '0',
          'sv_maxclients' => '16',
          '.' => '.',
          'voteFlags' => '65535',
          'g_heavyWeaponRestriction' => '20',
          'version' => 'ET 2.56 linux-i386 Sep 10 2003',
          'P' => '-21---11222-12-1',
          'gamename' => 'etpro',
          'g_gametype' => '4',
          'sv_minPing' => '0',
          'mod_url' => 'http://etpro.anime.net/',
          'g_LTChargeTime' => '40000'
        };

=cut

