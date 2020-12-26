#!/usr/bin/perl
##############################################################################
#
#  ETS-RT -- Wolfenstein: Enemy Territory Real-Time Statistics
#  (c) Vladi Shabanski <cade@bis.bg> 2003-2005
#  http://soul.datamax.bg/~cade/away/ets
#
#  Developed for play.evrocom.net server ET community
#  http://play.evrocom.net
#
#  This software is distributed under GPL license, see COPYING for details.
#
#  $Id: ets-rt.pl,v 1.6 2005/06/19 20:21:30 cade Exp $
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

our $HERE         = $ENV{ 'IMPOSTOR_HERE' } || $ENV{ 'ETS_HERE' } || '127.0.0.1';  # bind address of the host machine
our $SERVER_IP    = $ENV{ 'ETS_SERVER_IP' };
our $SERVER_PWD   = $ENV{ 'ETS_SERVER_PWD' };
our $SEEN_FILE    = $ENV{ 'ETS_SEEN_FILE' };
our $QUOTES_FILE  = $ENV{ 'ETS_QUOTES_FILE' };
our $O_LOOP_TIME  = $ENV{ 'ETS_O_LOOP_TIME' } || 60; # 1 minute default
our $XPWINS_DIFF  = $ENV{ 'ETS_XPWINS_DIFF' } || 20; # minimum difference for xp wins theory calculation
our $PL_DIFF      = $ENV{ 'ETS_PL_DIFF' } || 2; # minimum team players count difference
our $REF_FILE     = $ENV{ 'ETS_REF_FILE' };
our $SCREENSHOTS  = $ENV{ 'ETS_SCREENSHOTS' } || '#../../screenshots';

$SERVER_IP .= ":27960" unless $SERVER_IP =~ /:\d+$/;

#$SERVER_IP = "203.22.13.13:27960";
#$SERVER_IP = "play.evrocom.net:27960";
#my @data = split /\n+/, rcon('!getstatus');
#my %data = split( /\\/, '.\.' . shift @data );
#print Dumper( \%data, \@data );
#sleep(2);
#print Dumper( rcon('!statusResponse') );
#exit;

### misc config ##############################################################

our $MOD = 0; # running mod 0 - etmain, 1 - etpro (autodetected)

### vars #####################################################################

our $SPREE_MIN  = 20;
our $SPREE_STEP = 5;
our %SPREE; # event/player -> count

our %BEST_SPREE;
our %BEST_SPREE_PLAYER;

our $GAME_NO;
our $SEEN = {};

##############################################################################

our %REFEREES;

our %WHO;

### messages #################################################################

our %MSG = (
  HEAD         => "^8***",
  MSG          => "^8[MSG]",
  SPREE        => "^7[PLAYER]^8 is in [SPREE] spree with ^7[COUNT]^8 (record: ^7[BEST_SP]^8)",
  SPREE_END    => "^7[PLAYER]'s^8 [SPREE] spree is ^7over^8 with ^7[COUNT]^8 in a row",
  SPREE_RECORD => "^7[PLAYER]^8 set [SPREE] spree ^7RECORD^8 with ^7[COUNT]^8 in a row",
  SPREE_BEST   => "[SPREE] spree ^7RECORD^8 is ^7[COUNT]^8 in a row scored by ^7[PLAYER]^8",
  SEEN         => "^7[PLAYER]^8 last seen ^7[TIME]^8 (^7[AGO]^8 ago)",
  SEEN_UNKNOWN => "^7[PLAYER]^8 is unknown",
  TOO_MANY     => "^7[COUNT]^8 players found matching (^7[PLAYER]^8)",
  WHO_IS_WHO   => "^7[PLAYER]^8^1[REF]^8 is known as ^7[WHO]^8 (^7[AGE]^8)",
  WHO_HIMSELF  => "^7[PLAYER]^8^1[REF]^8 is best known as himself (^7[AGE]^8)",
  XP_NOBALANCE => "^1WARNING^8 XP Disbalance (^7[DIFF]^8 percents, [DES])",
  PL_NOBALANCE => "^1WARNING^8 Team Players Count Disbalance (^7[DIFF]^8)",
           );
our %MSG_BP = (
  HEAD         => "^8***",
  MOONLIGHT    => "^1moonlight gravity mode engaged^7",
  WELCOME_REF  => "^8Welcome referee ^7[PLAYER]^8",
           );

### main() here ##############################################################

$TRANSLATION = load_hash( $ENV{'ETS_TRANSLATION'} ) || {};

$REVISION = '$Revision: 1.6 $';
$ETS_VER = $1 if $REVISION =~ /([\d\.]+)/;
$CREDITS = "<small><a href=http://cade.datamax.bg/away/ets><b>ETS-RT2 $ETS_VER</b></a> by 2003-2005 (c) <a href=mailto:cade\@bis.bg>&lt;cade\@bis.bg&gt;</a></small>";

# init -----------------------------------------------------------------------

fill_whoiswho();

# main -----------------------------------------------------------------------

-e $LOG_CON_FILE or logger( "FATAL: cannot find $LOG_CON_FILE ($!)\n" );
my $FH = new IO::File( "/usr/bin/tail -f $LOG_CON_FILE |" ) or logger( "FATAL: cannot open $LOG_CON_FILE ($!)\n" );
my $flags = '';
fcntl( $FH, F_GETFL, $flags ) or logger( "ERROR: cannot get flags $LOG_CON_FILE ($!)" );
$flags |= O_NONBLOCK;
fcntl( $FH, F_SETFL, $flags ) or logger( "ERROR: cannot set flags $LOG_CON_FILE ($!)" );
#my $FH_S = IO::Select->new();
#$FH_S->add($FH);

#my $FH = File::Tail->new( name               => $LOG_CON_FILE,
#                          ignore_nonexistant => 1,
#                        );
#$FH->nowait(1);                       


load_ref_file();

my $break_main_loop = 0;

$SIG{ 'INT'  } = sub { $break_main_loop = 1; };
$SIG{ 'HUP'  } = sub { $break_main_loop = 1; };   
$SIG{ 'TERM' } = sub { $break_main_loop = 1; };   

$SEEN = retrieve( $SEEN_FILE ) if $SEEN_FILE and -e $SEEN_FILE;

# runtime vars
my %last_server;
my $last_game_time;
my %client;
my %client_name_map;
my $time;
my $exit;

while(4)
  {
  # $_ = $FH->read();
  $_ = <$FH>;
  last if $break_main_loop;
  online_status() if $OUTPUT_DIR and -d $OUTPUT_DIR;
  sleep(1) and next if $_ eq '';
  # logger( "DEBUG: CON: $_" );
  $time = localtime();

  if( /gamename: (\S+)/ ) { h_gamename( $1 ); next; }
  if( /^Userinfo: +\\(.+)/i )
    {
    fill_whoiswho_line( $1, $GAME_NO );
    next;
    };
  if( /^InitGame:\s*(.*)$/o )
    {
    load_ref_file();
    $GAME_NO++;
    $exit = 0;
    $last_game_time = $time;
    %last_server = split /\\/, "\\$1";
    # detect new etpro version game
    if ( $last_server{ 'gamename' } eq 'etpro' ) 
      {
      # logger( "INFO: etpro mode detected" );
      $MOD = 1;
      }
    next;
    }
  if( /Exit:/o )
    {
    $last_server{ 'TIMELIMIT' } = /Timelimit/ ? 1 : 0;
    $exit = 1;
    next;
    }
  if( $exit and /^ShutdownGame/o )
    {
    h_spree_end( $_ ) for keys %SPREE;
    %SPREE = ();
    %BEST_SPREE = ();
    %BEST_SPREE_PLAYER = ();
    next;
    }
  if( /^ClientUserinfoChanged: (\d+) (.+)/io )
    {
    # n\xwayBG\t\2\c\4\r\0\m\0000000\s\0000000\dn\chromosome\dr\0\w\10\lw\10\sw\41\mu\0\ref\0
    my $id = $1;
    my $data = $2;
    $client{ $id } = { split /\\/, $data };
    my $n = $client{ $id }{ 'n' };
    $SEEN->{ $n } = time();
    store( $SEEN, $SEEN_FILE ) if $SEEN_FILE;
    
    $client_name_map{ $n } = $id;
    $n =~ s/\^.//g;
    $client_name_map{ $n } = $id;
    }
  if( /Kill: (\d+) (\d+) (\d+): (.+) killed (.+) by MOD_([A-Z_0-9]+)/io )
    {
    my $k = $4;
    my $d = $5;
    my $w = $6;
    
    h_spree_end( $d );
    h_spree( 'FRAG', $k );
    }
  if( /^([a-z]+_Pack): (\d+) (\d+)/io )
    {
    my $i = $1; # item
    my $f = $client{ $2 }{ 'n' }; # from 
    my $t = $client{ $3 }{ 'n' }; # to
    h_spree( "$i disp", $f );
    h_spree( "$i coll", $t );
    }
  if( /^(Medic_Revive): (\d+) (\d+)/io )
    {
    my $i = $1; # item
    my $f = $client{ $2 }{ 'n' }; # from 
    my $t = $client{ $3 }{ 'n' }; # to
    h_spree( "MEDIC REVIVE", $f );
    }
  if( /^say(buddy)?:\s+(.+?):\s+([\!\?].+)$/ or /^etpro (privmsg):\s+(.+?)\s+to\s+.+?:\s+([\!\?].+)$/ )
    {
    my $buddy  = $1;
    my $player = $2;
    my $msg    = $3;
    
    # commands
    h_ref( $player ),   next if $msg =~ /^\!REF/i;
    h_unref( $player ), next if $msg =~ /^\!UNREF/i;
    h_moon( $player ),  next if $msg =~ /^\!MOON/i;
    h_999( $player ),   next if $msg =~ /^\!999/i;
    
    # queries
    h_best(),           next if uc $msg eq '?BEST';
    h_seen( $1 ),       next if uc $msg =~ /^\?SEEN\s+(\S+)/i;
    h_who( $1 ),        next if uc $msg =~ /^\?WHO\s+(\S+)/i;
    h_quote( $1 ),      next if uc $msg =~ /^\?(\S{2,})/i;
    next;
    }
  }

### SUPPORT #################################################################

sub load_ref_file
{
  return unless file_changed( $REF_FILE );
  %REFEREES = ();
  my @ref = split /[\r\n]+/, load_file( $REF_FILE );
  my $refc;
  for( @ref )
    {
    #9f797e990234534534540bafb92ffe96(-) nick
    next unless /^([0-9a-f]+)\(.*?\)\s+(\S+)/i;
    my $guid = uc $1;
    my $nick = $2;
    $refc++ unless exists $REFEREES{ $guid };
    $REFEREES{ $guid } = $nick;
    }
  logger( "INFO: $refc referees found in $REF_FILE" );  
  logger( Dumper( \%REFEREES ) );
}

### HANDLERS ################################################################
  
sub h_gamename
{
  my $game = shift;
}
  
sub h_spree
{
  my $event  = uc shift;
  my $player =    shift;
  return unless $player;
  
  DEBUG( "DEBUG: spree $event, $player, " . $SPREE{ $player }{ $event } ) if $SPREE{ $player }{ $event } > 0;
  
  $SPREE{ $player }{ $event }++;
  my $sp = $SPREE{ $player }{ $event };
  return if $sp < $SPREE_MIN;
  return if $sp % $SPREE_STEP;
  if( $sp > $BEST_SPREE{ $event } )
    {
    $BEST_SPREE{ $event } = $sp;
    $BEST_SPREE_PLAYER{ $event } = $player;
    et_print( 'SPREE_RECORD', SPREE => $event, PLAYER => $player, COUNT => $sp )
    }
  else
    {
    et_print( 'SPREE', SPREE => $event, PLAYER => $player, COUNT => $sp, BEST_SP => $BEST_SPREE{ $event } );
    }
}

sub h_spree_end
{
  my $player = shift;
  return unless $player;

  for my $event ( keys %{ $SPREE{ $player } } )
    {
    my $sp = $SPREE{ $player }{ $event };
    next if $sp < $SPREE_MIN;
    if( $sp > $BEST_SPREE{ $event } )
      {
      $BEST_SPREE{ $event } = $sp;
      $BEST_SPREE_PLAYER{ $event } = $player;
      et_print( 'SPREE_RECORD', SPREE => $event, PLAYER => $player, COUNT => $sp )
      }
    else
      {
      et_print( 'SPREE_END', SPREE => $event, PLAYER => $player, COUNT => $sp );
      }  
    }
  delete $SPREE{ $player };
}

sub h_best
{
  for my $event ( keys %BEST_SPREE )
    {
    my $player = $BEST_SPREE_PLAYER{ $event };
    my $sp     = $BEST_SPREE{ $event };
    et_print( 'SPREE_BEST', SPREE => $event, PLAYER => $player, COUNT => $sp )
    }
}

sub h_seen
{
  my $player = lc shift;
  $player =~ s/\^.//g;
  
  my $pl;
  my $tm;
  my $c;
  while( my ( $k, $v ) = each %$SEEN )
    {
    my $kk = $k;
    $kk =~ s/\^.//g;
    $kk = lc $kk;
    next if index( $kk, $player ) < 0;
    $c++;
    $pl = $k;
    $tm = $v;
    }
  et_print( 'TOO_MANY', PLAYER => $player, COUNT => $c ) and return if $c > 1;
  et_print( 'SEEN_UNKNOWN', PLAYER => $player ) if $c == 0;
  if( $c == 1 )
    {
    my $ago = time() - $tm;
    $ago = int($ago/60); # now in minutes
    $ago = sprintf "%dd %dh %dm", int(   $ago / ( 24 * 60 ) ), 
                                  int( ( $ago % ( 24 * 60 ) ) / 60 ),
                                  int( ( $ago % ( 24 * 60 ) ) % 60 );
    et_print( 'SEEN', PLAYER => $pl, TIME => scalar(localtime($tm)), AGO => $ago );
    }
}

sub h_who
{
  my $player = lc shift;
  $player =~ s/\^.//g;
  
  my $pb = rcon_pb_sv_plist() or return;
  
  my $g; # found guid
  my $c; # founds count
  my $p; # player name (iterator)
  my $n; # found name
  my $r; # referee
  my $a = 'n/a';
  for $p ( keys %$pb )
    {
    my $pp = $p;
    $pp = lc $pp;
    $pp =~ s/\^.//go;
    next if index( $pp, $player ) < 0;
    $c++;
    $g = uc $pb->{ $p }{ 'GUID' };
    $a = uc $pb->{ $p }{ 'AGE' };
    my $ref = $pb->{ $p }{ 'REF_ID' };
    $r = "(R:$ref)" if $ref;
    $n = $p;
    }
  et_print( 'TOO_MANY', PLAYER => $player, COUNT => $c ) and return if $c > 1;
  my ( $pf, $cf ) = hash_max( $WHO{ $g } );
  et_print( ( $n eq $pf ? 'WHO_HIMSELF' : 'WHO_IS_WHO' ) , PLAYER => $n, WHO => $pf, AGE => $a, REF => $r ) if $c > 0;
}

our @QUOTES;
sub h_quote
{
  my $word = shift;
  @QUOTES = `cat $QUOTES_FILE` unless @QUOTES;
  
  my $border = $QUOTES[-1];
  while(4)
    {
    my $q = shift @QUOTES;
    push @QUOTES, $q;
    last if $q eq $border;
    if( $q =~ s/(\Q$word\E)/^7$1^8/gi )
      {
      et_print( 'MSG', MSG => $q );
      last;
      }
    }
}

sub h_ref
{
  my $player  = shift;
  $player =~ s/\^.//g;

  # return unless $MOD == 1;
  my $pb = rcon_pb_sv_plist();
  return unless $pb->{ $player }{ 'REF_ID' };
  rcon( "ref referee $player" );
  et_print( 'WELCOME_REF', PLAYER => $pb->{ $player }{ 'REF_ID' } );
  logger( "!ref: [$player] -> [" . $pb->{ $player }{ 'REF_ID' } . "] " . Dumper( $pb->{ $player } ) );
}

sub h_unref
{
  my $player  = shift;
  $player =~ s/\^.//g;

  # return unless $MOD == 1;
  my $pb = rcon_pb_sv_plist();
  rcon( "ref unreferee $player" ) if $pb->{ $player }{ 'REF_ID' };
  logger( "!unref: " . Dumper( $pb->{ $player } ) );
}

sub h_moon
{
  my $player  = shift;
  $player =~ s/\^.//g;

  # return unless $MOD == 1;
  my $pb = rcon_pb_sv_plist();
  return unless $pb->{ $player }{ 'REF_ID' };
  rcon( "g_gravity 80" );
  et_print( 'MOONLIGHT' );
  logger( "!moon: " . Dumper( $pb->{ $player } ) );
}

sub h_999
{
  my $player  = shift;
  $player =~ s/\^.//g;
  
  my $pb = rcon_pb_sv_plist();
  return unless $pb->{ $player }{ 'REF_ID' };

  my $st = rcon_status();
  logger( "!999: " . Dumper( $pb, $st ) );
  
  for my $p ( keys %$st )
    {
    next if $st->{ $p }{ 'PING' } ne '999';
    my $slot = $st->{ $p }{ 'SLOT' };
    rcon( "ref remove $slot" );
    }
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
    $data{ $pb[8] }{ 'REF_ID' } = $REFEREES{ $pb[1] };
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

### ONLINE STATUS ###########################################################

our $O_EXEC_TIME;
our $O_LAST_MAP;
our $O_LAST_TIME;
our $O_LAST_OK;
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
    my $class = substr( $CLASS{ $client{ $client_name_map{ $name } }{ 'c' } }, 0, 1 ) || '?';
    my $href = escape_name( $name );
    my $ref = $client{ $client_name_map{ $name } }{ 'ref' } ? '[ref]' : '';
    push @{ $pl{ $s } }, [ "($class) <a href=p_$href.html>" . substr( $name, 0, 25 ) . "</a> $ref", $xp, $ping  ];
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

  $ENV{ 'REFRESH' } = "<meta http-equiv=refresh content=$O_LOOP_TIME>";
  html_save( 'online', make_columns( "<img src=$SCREENSHOTS/$scr width=400 height=300>", $text ),
                       "<br>",
                       html_table( \@pdata )  );
  delete $ENV{ 'REFRESH' };                     
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

#############################################################################

sub fill_whoiswho
{
  open( my $i, $LOG_CON_FILE ) or die "$0: cannot fill WHOISWHO from $LOG_CON_FILE\n";
  while( <$i> )
    {
    $GAME_NO++ if /^InitGame:/;
    fill_whoiswho_line( $1, $GAME_NO ) if /^Userinfo: +\\(.+)/i;
    }
  close( $i );
}

our %SEEN_GN;
our $LAST_GN;
sub fill_whoiswho_line
{
  my $l  = shift; # userinfo line
  my $gn = shift; # game number
  
  my %h = split /\\/, $l;
  my $g = uc $h{ 'cl_guid' };
  my $n = $h{ 'name' };
  $n =~ s/\^.//go;
  if( $LAST_GN != $gn )
    {
    delete $SEEN_GN{ $LAST_GN };
    $LAST_GN = $gn;
    }
  return if $SEEN_GN{ $gn }{ $g }++;
  DEBUG("WHO: $g $n");
  $WHO{ $g }{ $n }++;
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

sub et_print
{
  my $msg_id = uc shift;
  my %opt    = @_;
  
  my $say  = $MOD ? 'qsay' : 'say';
  my $head = $MSG{ 'HEAD' };
  my $msg = $MSG{ $msg_id } || $MSG_BP{ $msg_id };
  
  $say = 'bp' if $MOD and $MSG_BP{ $msg_id };
  
  $msg =~ s/\[([^\]]+)\]/$opt{$1}/g;
  
  rcon( "$say $head $msg" );
}

sub rcon
{
  my $command = shift;
  
  DEBUG( "RCON DUMMY: $command" );
  
  my $sock = IO::Socket::INET->new( PeerAddr  => $SERVER_IP,
                                    Proto     => 'udp',
                                    LocalAddr => $HERE,
                                    Broadcast => '1' ) or 
  logger( "ERROR: cannot connect $SERVER_IP" );
      
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
  while( my @ready = $sel->can_read( 1 ) )
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

