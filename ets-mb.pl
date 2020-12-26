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
#  $Id: ets-mb.pl,v 1.11 2005/05/22 14:41:56 cade Exp $
#
##############################################################################
use FindBin;
use lib $ENV{ 'ETS_LIB' } || "$FindBin::Bin/ets_lib";
use Data::Dumper;
use ets;
use IO::Socket::INET;
use IO::Select;
use Storable;
use strict;

$| = 1;

our $DB_FILE      = $ENV{ 'ETS_DB_FILE' } || 'ets-mb.db';  # bind address of the host machine

our $MASTER = 'etmaster.idsoftware.com:27950';
our $QUERY  = 'getservers 0 84';

##############################################################################

$REVISION = '$Revision: 1.11 $';
$ETS_VER = $1 if $REVISION =~ /([\d\.]+)/;
$CREDITS = "<small><a href=http://cade.datamax.bg/away/ets><b>ETS-MB2 $ETS_VER</b></a> by 2003-2005 (c) <a href=mailto:cade\@bis.bg>&lt;cade\@bis.bg&gt;</a></small>";

my @srv;
my %srv;
my %stats;
my %store;

my %qsrv;

my $store = retrieve( $DB_FILE ) if -e $DB_FILE;
%store = %$store if $store;
#@srv   = @{ $store{ '@srv' } || [] };
#%srv   = %{ $store{ '%srv' } || {} };
%stats = %{ $store{ '%stats' } || {} };

@srv = query_master();
query_servers( \@srv, \%qsrv );
@srv = keys %qsrv;
for my $srv ( @srv )
  {
  my $res = $qsrv{ $srv };
  $res =~ s/^\xff\xff\xff\xffstatusResponse\x0a\\//;
  my @players = split /\n/, $res;
  $res = shift @players;
  my %res = split /\\/, $res;
  $res{ 'players' } = @players;
  $srv{ $srv } = \%res;
  }
=pod
=cut

for my $srv ( @srv )
  {
  my $players = $srv{ $srv }{ 'players' };
  next unless $players > 0;
  $stats{ 'maps' }{ $srv{ $srv }{ 'mapname'  } }++;
  $stats{ 'mods' }{ $srv{ $srv }{ 'gamename' } }++;
  $stats{ 'mods_versions' }{ $srv{ $srv }{ 'gamename' } . ': ' . $srv{ $srv }{ 'mod_version' } }++ if $srv{ $srv }{ 'mod_version' };
              
  my $gt = $srv{ $srv }{ 'g_gametype' };
  $gt = $GAMETYPE{ $gt } || $gt;
  $stats{ 'gametype' }{ $gt }++;

  my $gml = $srv{ $srv }{ 'g_maxlives' };
  $stats{ 'maxlives' }{ $gml }++ if $gml > 0;
  
  $stats{ 'version' }{ $srv{ $srv }{ 'version' } }++;
  
  $stats{ 'popular' }{ $srv }{ 'data' } ||= [];
  push @{ $stats{ 'popular' }{ $srv }{ 'data' } }, $players;
  my $sum;
  my $cnt;
  my @data = @{ $stats{ 'popular' }{ $srv }{ 'data' } };
  $cnt = @data;
  $sum += $_ for @data;
  $stats{ 'popular' }{ $srv }{ 'cnt' } = $cnt;
  $stats{ 'popular' }{ $srv }{ 'sum' } = $sum;
  $stats{ 'popular' }{ $srv }{ 'rank' } = sprintf( ( $cnt > 0 ? "%.2f" : "n/a" ), $sum / $cnt + $cnt * 3 );
  $stats{ 'popular' }{ $srv }{ 'name' } = $srv{ $srv }{ 'sv_hostname' };
  }
for( keys %{ $stats{ 'maps' } } )
  {
  my $map_e = escape_name( $_ );
  $href{ $_ } = $map_e;
  html_save( "map_$map_e",    mod_servers( "[T:servers with map] $_", EMPTY => 0, FLOOR => 999999, FILTER => 'mapname', VALUE => $_ ) );
  }
for( keys %{ $stats{ 'mods' } } )
  {
  my $mod_e = escape_name( $_ );
  $href{ $_ } = $mod_e;
  html_save( "mod_$mod_e",    mod_servers( "[T:servers with mod] $_", EMPTY => 0, FLOOR => 999999, FILTER => 'gamename', VALUE => $_ ) );
  }


html_save( 'index' );
html_save( 'full',   mod_servers( "[T:full  servers]", EMPTY => 0 ) );
html_save( 'empty',  mod_servers( "[T:empty servers]", EMPTY => 1 ) );
html_save( 'all',    mod_servers( "[T:all   servers]", FLOOR => 999999 ) );

html_save( 'maps',   mod_hash_stats( "[T:servers running maps]", $stats{ 'maps' }, HREF_PREFIX => 'map_', NO_COLORS => 1 ) );
html_save( 'mods',   mod_hash_stats( "[T:servers running mods]", $stats{ 'mods' }, HREF_PREFIX => 'mod_', NO_COLORS => 1 ),
                     "<p>",
                     mod_hash_stats( "[T:servers running mods (with versions)]", $stats{ 'mods_versions' }, HREF_PREFIX => 'mod_', NO_COLORS => 1 ) );

html_save( 'popular', mod_popular( "[T:most popular servers]", ) );

html_save( 'stats',  mod_hash_stats( "[T:server gametypes]", $stats{ 'gametype' }, NO_COLORS => 1 ),
                     "<p>",
                     mod_hash_stats( "[T:max lives (for last man standing servers only)]", $stats{ 'maxlives' }, NO_COLORS => 1 ), 
                     "<p>",
                     mod_hash_stats( "[T:core server versions (no mods)]", $stats{ 'version' }, NO_COLORS => 1 ), 
                     );

#$store{ '@srv' } = \@srv;
#$store{ '%srv' } = \%srv;
$store{ '%stats' } = \%stats;
store( \%store, $DB_FILE );

##############################################################################

sub mod_servers
{
  my $title = shift;
  my %opt   = @_;
  my $text;

  my @data;
  push @data, [ 'HEAD', "[>5%]#", "[45%][T:Server]", "[15%][T:IP]", "[15%][T:Map]", "[>10%][T:Players]", "[10%][T:Mod]" ];

  my $filter = $opt{ 'FILTER' };
  my $value  = $opt{ 'VALUE' };

  my @list = @srv;
  if( exists $opt{ 'EMPTY' } )
    {
    @list = grep { $opt{ 'EMPTY' } ? $srv{ $_ }{ 'players' } == 0 : $srv{ $_ }{ 'players' } > 0 } @srv;
    }
  if( $filter and $value )
    {
    @list = grep { $srv{ $_ }{ $filter } eq $value } @srv;
    }
  @list = sort { $srv{ $b }{ 'players' } <=> $srv{ $a }{ 'players' } } @list;
  
  for( @list )
    {
    my $host  = $srv{ $_ }{ 'sv_hostname' };
    $host     = color_name( substr( $host, 0, 50 ) );
    my $map   = $srv{ $_ }{ 'mapname' };
    my $pl    = $srv{ $_ }{ 'players' };
    my $mod   = $srv{ $_ }{ 'gamename' };
    my $map_e = escape_name( $map );
    my $mod_e = escape_name( $mod );
    push @data, [ '', '(ROW)', $host, $_, "<a href=!map_$map_e.html>$map</a>", $pl, "<a href=!mod_$mod_e.html>$mod</a>" ];
    }

  push @data, [ 'FOOT', '', '', '', '', '(SUM)', '' ];
  
  return "<h3 class='ets'>$title</h3>" . html_table( \@data, FLOOR => $opt{ 'FLOOR' } );
}

sub mod_popular
{
  my $title = shift;
  my %opt   = @_;
  my $text;

  my @data;
  push @data, [ 'HEAD', "[>5%]#", "[45%][T:Server]", "[15%][T:IP]", "[>15%][T:Players]", "[>10%][T:Hits]", "[>10%][T:Rank]" ];

  for my $srv ( keys %{ $stats{ 'popular' } } )
    {
        push @data, [ '', '(ROW)', 
                        color_name( substr( $stats{ 'popular' }{ $srv }{ 'name' }, 0, 50 ) ),
                        $srv,
                        $stats{ 'popular' }{ $srv }{ 'sum' },
                        $stats{ 'popular' }{ $srv }{ 'cnt' },
                        $stats{ 'popular' }{ $srv }{ 'rank' },
                        ];
    }

  push @data, [ 'FOOT', '', '', '', '', '', '(AVE)' ];
  
  return "<h3 class='ets'>$title</h3>" . html_table( \@data, FLOOR => $opt{ 'FLOOR' }, SORT => 6 );
};
##############################################################################
=pod
sub test_dump
{
  my @labels = qw( mapname players gamename g_gametype g_heavyweaponrestriction );
  
  my $c = 0;
  my %data;
  for my $srv ( @srv )
    {
    my $res = $srv{ $srv };
    $res =~ s/^\xff\xff\xff\xffstatusResponse\x0a\\//;
    $res =~ s/^([^\n]+)(.*)$/$1/;
    my @players = split /\n/, $res;
    $res = shift @players;
    my %res = split /\\/, $res;
    for( @labels )
      {
      $data{ $srv }{ $_ } = $res{ $_ };
      }
    $data{ $srv }{ 'players' } = @players;
    $data{ $srv }{ '@' } = $res;
    print STDERR "$srv ($c/".@srv.")\n";
    $c++;
    }
  
  #print join( ':', @labels ), "\n";
  for my $srv ( @srv )
    {
    print $srv, ':';
    for( @labels )
      {
      print $data{ $srv }{ $_ }, ':';
      }
    print "\n";
    }
  
  use Data::Dumper;
  print "\n\n\n+++\n\n\n", Dumper( \%data );
}
=cut
##############################################################################

sub query_servers
{
  my $list = shift;
  my $data = shift;
  
  my @list = @$list;
  
  my $sock = IO::Socket::INET->new( Proto => 'udp', Timeout => 1, Blocking => 0 ) or 
             print STDERR "udp error: cannot connect: $!\n", return undef;
  
  my $sel = IO::Select->new();
  $sel->add($sock);
  
  my $expire;
  while(4)
    {
    my $to = shift @list;
    my $cnt = @list;
    $expire = time() + 30 if ! $expire and $cnt == 0;
    print STDERR "[$cnt] sending to $to\n" if $cnt > 0;
    if( $to =~ /^([\d\.]+):(\d+)$/ )
      {
      $to = sockaddr_in($2, inet_aton($1));
      $sock->send( "\xff\xff\xff\xffgetstatus\n", 0, $to );
      }
    #print STDERR "[$cnt] awating data...\n";
    my $from = $sock->recv( $_, 4096 ) if $sel->can_read( 1 );
    $_ = undef unless $from;
    if( ! $_ )
      {
      last if $expire and time() > $expire;
      next;
      }
    my ( $rport, $raddr ) = sockaddr_in( $from );
    $raddr = inet_ntoa( $raddr );
    $data->{ "$raddr:$rport" } .= $_;
    #print STDERR "[$cnt] received from $raddr:$rport (".length($_)." chars)\n";
    last unless $_ or @list;
    #print STDERR "[$cnt]\n";
    };
}

sub udp_query
{
  my %args = @_;
  
  my $sock = IO::Socket::INET->new( PeerAddr  => $args{ 'SERVER' },
                                    Proto     => 'udp', ) or 
             print STDERR "udp error: cannot connect: $!\n", return undef;
  
  my $sel = IO::Select->new();
  $sel->add($sock);
  
  $sock->send( "\xff\xff\xff\xff".$args{'QUERY'}."\n" );
  
  my $data;
  while( my @ready = $sel->can_read( 1 ) )
    {
    my ( $rport, $raddr ) = $sock->recv( $_, 4096 );
    last unless $_;
    $data .= $_;
    };
  return $data;
}

sub query_master
{
  my %args = @_;

  my $res = udp_query( SERVER => $MASTER, QUERY => $QUERY );
  
  my @lines = split /\xff\xff\xff\xffgetserversResponse/, $res;
  my @data = split /\\/, join '', @lines;
  
  my @addr;
  for( @data )
    {
    next if /^EOT/;
    next if length($_) ne 6;
    my ( $a1, $a2, $a3, $a4, $port ) = unpack( "CCCCn", $_ );
    push @addr, "$a1.$a2.$a3.$a4:$port";
    }
  
  return @addr;
}

sub hex_dump
{
  my $data = shift;

  my @data = split //, $data;
  $data = undef;
  my $c = 0;
  my $ascii;
  while(@data)
    {
    $_ = shift @data;
    if( $c % 16 == 0 )
      {
      $data  .= "[$ascii]\n" if $c > 0;
      $data  .= sprintf "%8X ", $c;
      $ascii  = '';
      }
    $ascii .= ( ord( $_ ) >= 32 and ord( $_ ) < 128 ) ? $_ : '.';
    $data  .= sprintf "%2X ", ord( $_ );
    $c++;
    }
  $data .= "\n";
  
  return $data;
}

### EOF ######################################################################

=pod

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
-----------------------------------------------------------------------------
          'protocol' => '83',
          'sv_maxRate' => '10000',
          'g_minGameClients' => '2',
          'sv_allowAnonymous' => '0',
          'mapname' => 'oasis',
          'g_axismaxlives' => '0',
          'g_needpass' => '0',
          'sv_hostname' => '^1NI^3MB^4US ^NETPro Server',
          '.URL' => 'http://nimbus.braila.astral.ro',
          'sv_punkbuster' => '1',
          'g_alliedmaxlives' => '0',
          'mod_version' => '3.1.9',
          'g_balancedteams' => '1',
          'g_antilag' => '1',
          'g_maxlivesRespawnPenalty' => '0',
          'g_medicChargeTime' => '45000',
          'sv_floodProtect' => '0',
          'g_engineerChargeTime' => '30000',
          'g_friendlyFire' => '1',
          'g_bluelimbotime' => '20000',
          'g_redlimbotime' => '30000',
          'g_soldierChargeTime' => '20000',
          'g_maxGameClients' => '0',
          'sv_privateClients' => '0',
          'players' => 0,
          'timelimit' => '30',
          'g_covertopsChargeTime' => '30000',
          'g_voteFlags' => '0',
          'sv_maxPing' => '180',
          'sv_minguidage' => '0',
          'g_maxlives' => '0',
          'sv_maxclients' => '12',
          'voteFlags' => '4352',
          'g_heavyWeaponRestriction' => '100',
          'gamestartup' => '03/13/05 19:41:24',
          'version' => 'ET 2.56 linux-i386 Sep 10 2003',
          'gamename' => 'etpro',
          'g_gametype' => '4',
          'sv_minPing' => '0',
          'mod_url' => 'http://etpro.anime.net/',
          'g_LTChargeTime' => '40000'

=cut

