#!/usr/bin/perl
##############################################################################
#
#  ETS -- Wolfenstein: Enemy Territory Statistics
#  (c) Vladi Shabanski <cade@bis.bg> 2003-2005
#  http://soul.datamax.bg/~cade/away/ets
#
#  Developed for play.evrocom.net server ET community
#  http://play.evrocom.net
#
#  This software is distributed under GPL license, see COPYING for details.
#
#  $Id: ets.pl,v 1.11 2005/06/01 12:52:35 cade Exp $
#
##############################################################################
use FindBin;
use lib $ENV{ 'ETS_LIB' } || "$FindBin::Bin/ets_lib";
use Storable;
use Data::Dumper;
use POSIX qw( strftime );
use ets;
use strict;

### GET PARAMETERS ###########################################################

my $help = $ARGV[0];

print "CONFIG:
  log_file     = $LOG_FILE  
  output_dir   = $OUTPUT_DIR
  web_prefix   = $WEB_PREFIX
  web_dir      = $WEB_DIR   
  theme        = $THEME
  min_players  = $MIN_PLAYERS
  floor        = $FLOOR
  tops_floor   = $TOPS_FLOOR
  score_min    = $SCORE_MIN
";

die "usage: . config && $0
"  if $help =~ /^--?h(elp)?/i or $LOG_FILE eq '';

### CONFIG ###################################################################

our $MOD = 0; # running mod 0 - etmain, 1 - etpro (autodetected)

# files_dir is the web path of the dir where the web-content should be written to
# my $files_dir = "/mk/gaming/stats/et";
#my $files_dir = "/etstats";

# Sascha:
# this dir is the one you use to call the referred pages from. There is no difference for
# $WEB_DIR and $file_dir as long you do _not_ run in a postnuke (or considerable) content.
# Be sure you have htmlloader.php or a similar Content-Caller like PostWrap installed if
# you use this calling method!
#
# my $WEB_PREFIX = "/postnuke/html/htmlloader.php?content=" . $files_dir;
#my $WEB_PREFIX = $files_dir;

###MAIN#######################################################################

$NAME_MAP    = load_hash( $ENV{'ETS_NAME_MAP'} ) || {};

$REVISION = '$Revision: 1.11 $';
$ETS_VER = $1 if $REVISION =~ /([\d\.]+)/;
$CREDITS = "<small><a href=http://cade.datamax.bg/away/ets><b>ETS2 $ETS_VER</b></a> by 2003-2005 (c) <a href=mailto:cade\@bis.bg>&lt;cade\@bis.bg&gt;</a></small>";

$NAME_MAP    = load_hash( $ENV{'ETS_NAME_MAP'} ) || {};
$CLAN_MAP    = load_hash( $ENV{'ETS_CLAN_MAP'} ) || {};
$TRANSLATION = load_hash( $ENV{'ETS_TRANSLATION'} ) || {};

DEBUG( "----------NAME_MAP----------\n" . Dumper( $NAME_MAP ) );
DEBUG( "----------CLAN_MAP----------\n" . Dumper( $CLAN_MAP ) );

my %kil; # koi-kogo e kill-nal
my %ded; # ...i obratnoto

my %nam;

my %unif_taken; # uniforms taken
my %unif_lost; # uniforms lost

my %noise; # noise in words :)

my %class_last; # last classes per player
my %class; # classes per player

my %side_last; # last side per player
my %side; # side per player

my %global_class;
my %global_side;

my %classes;
my %sides;

my %client; # clients info
my %client_id; # reverse map: name -> id

my $minute; # used for top kills per minute
my %kpm_temp;
my %kpm_game; # which minute in which game is
my %kpm;

my %fsp_temp;
my %fsp_temp_time;
my %fsp_time;
my %fsp_class;
my %fsp_game; # which minute in which game is
my %fsp;      # frag spree

my %top_td;     # team damage

my %conn_time;  # connect time
my %time_waste; # time "wasted" :)

my @games; # all games
my %games; # game time->game data
my @trans; # last game transcription

my %player; # stats from weapon stats, same as in @games

my %weapons; # stats total
my %skills;  # skills total

my %top_snipe;   # top usage of sniper weapons
my %top_harvest; # top harvest ladder

my %top_ranks; # top rank ladder

my %members; # clan members

my %jerks; # players on winning team when XP differs more than 20% or more

# resolver
my %ip;        # ip->name(s)
my %ip_rev;    # name->ip(s)
my %guid;      # guid->name(s)
my %guid_rev;  # name->guid(s)
my %same_ip;   # name->name(s) from the same ip
my %same_guid; # name->name(s) from the same guid

#-----------------------------------------------------------------------------

my %snipe_head;
$snipe_head{ 'NAME' }         = "<1>[80%][T:Player]";
$snipe_head{ 'ALL' }          = "<2>[>5%][T:ALL]";
$snipe_head{ 'GARAND_SCOPE' } = "<3>[>5%][T:GAR]";
$snipe_head{ 'K43_SCOPE' }    = "<4>[>5%][T:K43]";
$snipe_head{ 'FG42SCOPE' }    = "<5>[>5%][T:FG42]";

my %ranks_head;
$ranks_head{ 'NAME' }         = "<1>[30%][T:Player]";
$ranks_head{ 'RANK' }         = "<2>[20%][T:Rank]";
$ranks_head{ 'XP' }           = "<3>[>10%][T:XP]";
$ranks_head{ 'RANKXP' }       = "<4>[>10%][T:Value]";
$ranks_head{ 'GAME' }         = "<5>[30%][T:In Which Game]";

#-----------------------------------------------------------------------------

setpriority( 0, 0, 19 ) if ! $ENV{ 'ETS_FULL_SPEED' } and $^O ne "MSWin32";

#log_check_weaponstats(); die; # 31685
read_log_file();
read_con_file();

#-----------------------------------------------------------------------------

html_save( 'online', 'not available' ) unless -e "$OUTPUT_DIR/online.html";

print STDERR "processing data...\n";

$nam{ '*WORLD*' }++;
# remove fake players
for my $k ( keys %nam )
  {
  next if $k eq '*WORLD*';
  next if $k =~ /^!/;
  next if $k =~ /^MAP:/;
  delete $nam{ $k } if $k eq 'unknown';
  # never reached XP above 100
  delete $nam{ $k } unless $player{ $k }{ 'TOP_SCORE' } > $SCORE_MIN;
  }

$NAM_COLOR{ 'AXIS' } = "^1AXIS";
$NAM_COLOR{ 'ALLIES' } = "^4ALLIES";
$NAM_COLOR{ 'SPECTATORS' } = "^2SPECTATORS";

# fix names links
for my $k ( keys %nam )
  {
  $href{ $k } = escape_name( $k );
  $members{ get_clan( $k ) }{ $k }++;
  }

#-----------------------------------------------------------------------------

if( $LOG_PB_FILE )
  {
  my $pbc = 0;
  my $cnt = 0;
  print STDERR "processing PB log file: $LOG_PB_FILE\n";
  
  my @data;
  
  my %seen;
  
  open my $i, $LOG_PB_FILE;
  while(<$i>)
    {
    s/[\r\n]+$//o;
    # [10.21.2003 18:14:40] VIOLATION (WALLHACK) #60184: ^$WARIOR (slot #2) Violation (WALLHACK) #60184 [9d92d8d22b8fc763555a4f0683b7af1c(-) 217.10.250.23:27960]
    /\[([^\]]+)\]\s*VIOLATION\s*\(([^:]+)\)\s*#(\d+):\s*(.+?)\s*\(slot #\d+\).+?([\d\.\:]+)\]$/io;
    my $time = $1;
    my $viol = $2;
    my $vid  = $3;
    my $name = $4;
    my $addr = $5;
    
    $name =~ s/\^.//g;
    
    next unless $vid >= 50_000; # PB docs says violations over 50k are cheats
    
    next if $seen{ "$viol|$name" }++;
    
    # print STDERR "$time | $viol | $name | $addr\n";
    my $cname = color_name( $name );
    unshift @data, [ '', "<a href=!p_$href{$name}.html>$cname</a>", $viol, $vid, $name, $time, $addr ];
    pop @data if @data > 50;
    }
  close( $i );

  for( @data )
    {
    my $k = $_->[2] . '|' . $_->[4];
    $_->[4] = $seen{ $k };
    }
  
  unshift @data, [ 'HEAD', "[30%][T:Player]", "[<][T:Violation]", "[<][T:VID]", "[<][T:Count]", "[<][T:Time]", "[<][T:IP]" ];
  html_save( 'punks', "<h3 class='ets'>[T:hall of shame (busted punks)]</h3>", html_table( \@data, SORT => 4 ) );
  }
else
  {
  html_save( 'punks', "<h3 class='ets'>[T:hall of shame (busted punks)]</h3>", '[T:no information available]' );
  }

#-----------------------------------------------------------------------------

my %kpm_temp_game;
while( my ( $k, $v ) = each %kpm_temp )
  {
  my ( $max_k, $max_v ) = hash_max( $v );
  # $k = sprintf "%s  %s", scalar localtime( $max_k ), color_name( $k );
  $kpm{ $k } = $max_v;
  $kpm_temp_game{ $k } = $kpm_game{ $max_k };
  }
%kpm_game = %kpm_temp_game;

print STDERR "done\n";

#-----------------------------------------------------------------------------

print STDERR "writing statistics...\n";

my @games_text;

push @games_text, [ 'HEAD', 
                    '[>5%]#', 
                    '[15%][T:Map]',
                    '[20%][T:Game Started At]', 
                    '[>5%][T:Time]', 
                    '[>5%][T:Axis]', 
                    '[>5%][T:Ally]', 
                    '[10%][T:Winner]',
                    '[40%][T:Players]' ];
@games = reverse @games;
my $gc = 0; # game counter
for my $gr ( @games )
  {
  my $gid = $gr->{ 'ID' };
  my $ti  = $gr->{ 'TIME' };
  my $ma  = $gr->{ 'MAP' };
  my $gt  = $gr->{ 'GAME_TIME' };
  
  my $gts = sprintf "%dm%02ds", int( $gt / 60 ), int( $gt % 60 );
  my $tm = localtime( $ti );
  $tm =~ s/:\d\d / /; # remove seconds
  my $pl = sprintf "%02d", $gr->{ 'PLAYERS' };
  next unless $pl >= $MIN_PLAYERS;
  my $ww = $pl * 8;

  my $snipe = $gr->{ 'SNIPE' };
  $snipe->{ 'HEAD' } = \%snipe_head;
  for my $p ( keys %$snipe )
    {
    my $pc = color_name( $p );
    $snipe->{ $p }{ 'NAME' } = "<a class=t href=!p_$href{$p}.html>$pc</a>";
    }
  
  # now fix some links and info
  $games{ $gid } = $gr;
  my $des = $gr->{ 'DES' } = "$ma $pl\[T:pl.] $tm";
  
  push @games_text, [ '', 
                      '(ROW)', 
                      $ma, 
                      "<a href=!game_$gid.html>$tm</a>&nbsp;(<a href=!game_$gid\_trans.html>T</a>)",
                      $gts,
                      $gr->{ 'AXIS_XP' },
                      $gr->{ 'ALLIES_XP' },
                      get_winner( $gr->{ 'MAP' }, $gr->{ 'TIMELIMIT' } ),
                      "$pl <img src=#wp.gif height=10 width=$ww>"
                    ];

  for( keys %{ $gr->{ 'ITEMS' } } )
    {
    next if /^(HEAD|FOOT|COLS)$/;
    my $cn = color_name( $_ ) || '*unknown*';
    $gr->{ 'ITEMS' }{ $_ }{ 'NAME' } =  "<a href=!p_$href{$_}.html>$cn</a>";
    }
  
  html_save( "game_$gid", "<h3 class='ets'>[T:game at] $des</h3>",
                         mod_hash_stats_2d( '[T:Captures]/[T:Dynamites]/[T:Repairs]', $gr->{ 'ITEMS' } ),
                         "<p><h3 class='ets'>[T:Skills]</h3>",
                         single_game_stats( $gr, TYPE => 'SKILLS', SIDE => 'ALLIES' ),
                         single_game_stats( $gr, TYPE => 'SKILLS', SIDE => 'AXIS' ),
                         "<p><h3 class='ets'>[T:Shots and accuracy]</h3>",
                         single_game_stats( $gr, TYPE => 'SHOTS', SIDE => 'ALLIES' ),
                         single_game_stats( $gr, TYPE => 'SHOTS', SIDE => 'AXIS' ),
                         "<p><h3 class='ets'>[T:Damage]</h3>",
                         single_game_stats( $gr, TYPE => 'DAMAGE', SIDE => 'ALLIES' ),
                         single_game_stats( $gr, TYPE => 'DAMAGE', SIDE => 'AXIS' ),
                         mod_hash_stats_2d( "[T:Sniper kills]", $snipe, SORT => 2, FLOOR => 16 ),
                         "<p><h3 class='ets'>[T:Detailed Shots and accuracy]</h3>",
                         single_game_stats( $gr, TYPE => 'DETAILS' ),
                         "<p><a href=!game_$gid\_trans.html>[T:Transcription]</a>" );
  html_save( "game_$gid\_trans", "<h3 class='ets'>[T:game at] $tm [T:on] $ma [T:map], $pl [T:players]</h3>",
                         single_game_transcription( $gr, TYPE => 'TRANS' ) );
  $gc++;
  }

html_save( 'index' );
html_save( 'games', "<p><h3 class='ets'>[T:Last games: (approx. last 24 hours)]</h3><p>", 
                    html_table( [ grep /\S/, @games_text[0..50] ] ), 
                    "<p><a href=!games_all.html>[T:show all] $gc [T:games (long!)]</a>" );
                    
html_save( 'games_all', "<p><h3 class='ets'>[T:All] $gc [T:games]</h3><p>" . html_table( \@games_text, FLOOR => 1_000_000 ) );

my $map_text;
$map_text .= mod_map_stats( "Maps" );
$map_text .= mod_map_stats_ppl( "Maps per players count" );
$map_text .= "<p><small>Games with any team XP below $WINS_MINXP are ignored.<br>
             Minimum XP difference for 'XP Wins Theory' is $XPWINS_DIFF%</small><p>";
html_save( 'maps', $map_text );

html_save( "players", mod_players( CLAN => 0 ) );
html_save( "clans",   mod_players( CLAN => 1 ) );

html_save( 'p_sides' , make_columns(
                       mod_hash_stats( "AXIS ([T:totals per clan])", $sides{ 'AXIS' }, CLAN => 1, FLOOR => 16 ),
                       mod_hash_stats( "ALLIES ([T:(totals per clan])", $sides{ 'ALLIES' }, CLAN => 1, FLOOR => 16 ) ),
                       make_columns(
                       mod_hash_stats( "AXIS", $sides{ 'AXIS' }, FLOOR => 16 ),
                       mod_hash_stats( "ALLIES", $sides{ 'ALLIES' }, FLOOR => 16 ) ) );

for my $c ( '', 4..6 )
  {
  html_save( "kill$c", "sort by: 
                          <a href=!kill4.html>[T:Kills]</a>
                        | <a href=!kill5.html>[T:Deaths]</a>
                        | <a href=!kill6.html>[T:K:D Ratio]</a>",
                        "<p><h2>[T:kills/deaths/ratio]</h2><p>",
                        #mod_player_clan_stats( CLAN => 1, FLOOR => $FLOOR, SORT => $c || 4 ), 
                        mod_player_clan_stats( CLAN => 0, FLOOR => $FLOOR, SORT => $c || 4 ) );
  }


for my $k ( keys %nam )
  {
  my $text;
  my $clan = 0;
  $clan = 1 if $k =~ /^!/;
  $text .= mod_clan_members( "[T:clan members of] " . color_name( $k ), $k ) if $clan;
  
  $text .= make_columns( mod_hash_stats( "[T:sides played by] " . color_name( $k ), $side{ $k } ),
                         mod_hash_stats( "[T:classes played by] " . color_name( $k ), $class{ $k } ) );
  
  $text .= mod_top_rank_stats( "[T:top rank for] " . color_name( $k ), $k );
  $text .= mod_top_scores_stats( "[T:top scores for] " . color_name( $k ), $k );
  $text .= mod_player_weapons_stats( "[T:weapons' totals for] " . color_name( $k ), $k );
  $text .= mod_kill_killed( "[T:public relations for] " . color_name( $k ), $k );
  $text .= mod_games_for_player( "[T:last games in which participated] " . color_name( $k ), $k );
  
  $text .= "<p><a href=!p_r_$href{$k}.html>([T:resolver])</a>" if $LOG_CON_FILE;

  html_save( 'p_' . $href{$k}, $text );
  
  next unless $LOG_CON_FILE;
  
  $text = undef;
  
  $text .= mod_hash_stats( "[T:aliases for player] " . color_name( $k ), $same_guid{ $k } );
  $text .= mod_hash_stats( "[T:players from the same ip address(es)] " . color_name( $k ), $same_ip{ $k } );
  
  html_save( 'p_r_' . $href{$k}, $text );
  }

html_save( 'noise',    make_columns(
                       mod_hash_stats( "[T:noise in words by clan]", \%noise, CLAN => 1, FLOOR => 16 ),
                       mod_hash_stats( "[T:noise in words by player]", \%noise, FLOOR => 16 ),
                       ) );

for my $p ( keys %top_ranks )
  {
  my $pc = color_name( $p );
  $top_ranks{ $p }{ 'NAME' } = "<a class=t href=!p_$href{$p}.html>$pc</a>";
  my $r = int $top_ranks{ $p }{ 'RANKXP' } / 100000;
  $top_ranks{ $p }{ 'RANK' } = $RANK{ $r };
  $top_ranks{ $p }{ 'XP' } = $top_ranks{ $p }{ 'RANKXP' } - (100000 * $r); 
  my $gid = $top_ranks{ $p }{ 'GAME_ID' };
  $top_ranks{ $p }{ 'RANKXP' } = $top_ranks{ $p }{ 'RANKXP' };
  my $des = $games{ $gid }{ 'DES' };
  $top_ranks{ $p }{ 'GAME' } = "<a href=game_$gid\.html>$des</a>";
  }

$top_ranks{ 'HEAD' } = \%ranks_head;
html_save( 'ranks',   mod_hash_stats_2d( "[T:top rank in a single game]", \%top_ranks, SORT => 4, FLOOR => $FLOOR ));

for my $p ( keys %top_snipe )
  {
  my $pc = color_name( $p );
  $top_snipe{ $p }{ 'NAME' } = "<a class=t href=!p_$href{$p}.html>$pc</a>";
  }

$top_snipe{ 'HEAD' } = \%snipe_head;
html_save( 'covert',   mod_hash_stats_2d( "[T:top sniper kills in single game]", \%top_snipe, SORT => 2, FLOOR => 16 ),
                       make_columns(
                       mod_hash_stats_2d( "[T:GARAND]", \%top_snipe, SORT => 3, FLOOR =>  8 ),
                       mod_hash_stats_2d( "[T:K43]", \%top_snipe, SORT => 4, FLOOR =>  8 ),
                       mod_hash_stats_2d( "[T:FG42]", \%top_snipe, SORT => 5, FLOOR =>  8 ),
                       ),
                       make_columns(
                       mod_hash_stats( "[T:uniforms taken]", \%unif_taken, FLOOR => 32 ),
                       mod_hash_stats( "[T:uniforms lost]", \%unif_lost, FLOOR => 32 ),
                       ) );

html_save( 'kpm',      make_columns(
                       mod_kpm_stats( "[T:top kills per minute by clan]", CLAN => 1, FLOOR => 16 ),
                       mod_kpm_stats( "[T:top kills per minute by player]", CLAN => 0, FLOOR => 16 ),
                       ) );

html_save( 'fsp',      mod_fsp_stats( "[T:frag spree]", FLOOR => 16 ),
                       mod_fsp_stats( "[T:frag spree]", FLOOR => 8, CLASS => 'SOLDIER' ),
                       mod_fsp_stats( "[T:frag spree]", FLOOR => 8, CLASS => 'MEDIC' ),
                       mod_fsp_stats( "[T:frag spree]", FLOOR => 8, CLASS => 'ENGINEER' ),
                       mod_fsp_stats( "[T:frag spree]", FLOOR => 8, CLASS => 'FIELD_OPS' ),
                       mod_fsp_stats( "[T:frag spree]", FLOOR => 8, CLASS => 'COVERT_OPS' ),
                       );

html_save( 'waste',    make_columns(
                       mod_hash_stats( "[T:time wasted by clan]",   \%time_waste, TIMEFMT => 1, CLAN => 1, HEAD => "#,[<][T:Player],[>][T:Time],[<][T:Percentage]", FLOOR => 16 ),
                       mod_hash_stats( "[T:time wasted by player]", \%time_waste, TIMEFMT => 1,  HEAD => "#,[<][T:Clan],[>][T:Time],[<][T:Percentage]", FLOOR => 16 ),
                       ) );

html_save( 'classide', make_columns(
                       mod_hash_stats( "[T:sides played]", \%global_side ),
                       mod_hash_stats( "[T:classes played]", \%global_class ) ) );

html_save( 'top_td',   make_columns(
                       mod_hash_stats( "[T:'no friends' ladder by clan]",   \%top_td, NOP => 1, FLOOR => 16, CLAN => 1 ),
                       mod_hash_stats( "[T:'no friends' ladder by player]", \%top_td, NOP => 1, FLOOR => 16 ) ) );

html_save( 'harvest',  "<h3 class='ets'>[T:top figures for the harvest ladder]</h3>",
                       make_columns(
                       mod_hash_stats( "[T:health packs dispensed by player]", $top_harvest{ 'HEALTH_PACK/DISPENSED' }, FLOOR => 16 ),
                       mod_hash_stats( "[T:health packs collected by player]", $top_harvest{ 'HEALTH_PACK/COLLECTED' }, FLOOR => 16 ),
                       ),
                       make_columns(
                       mod_hash_stats( "[T:health packs dispensed by clan]", $top_harvest{ 'HEALTH_PACK/DISPENSED' }, FLOOR => 16, CLAN => 1 ),
                       mod_hash_stats( "[T:health packs collected by clan]", $top_harvest{ 'HEALTH_PACK/COLLECTED' }, FLOOR => 16, CLAN => 1 ),
                       ),
                       make_columns(
                       mod_hash_stats( "[T:ammo packs dispensed by player]", $top_harvest{ 'AMMO_PACK/DISPENSED' }, FLOOR => 16 ),
                       mod_hash_stats( "[T:ammo packs collected by player", $top_harvest{ 'AMMO_PACK/COLLECTED' }, FLOOR => 16 ),
                       ),
                       make_columns(
                       mod_hash_stats( "[T:ammo packs dispensed by clan]", $top_harvest{ 'AMMO_PACK/DISPENSED' }, FLOOR => 16, CLAN => 1 ),
                       mod_hash_stats( "[T:ammo packs collected by clan]", $top_harvest{ 'AMMO_PACK/COLLECTED' }, FLOOR => 16, CLAN => 1 ),
                       ), );

my $skills_totals = mod_skills_totals( "[T:score totals]" );
for my $c ( '', 4..11 )
  {
  html_save( "tops$c",   "[T:choose]:
                            <a href=!tops.html>[T:XP]</a>
                          | <a href=!tops4.html>[T:battle sense]</a>
                          | <a href=!tops5.html>[T:engineer]</a>
                          | <a href=!tops6.html>[T:medic]</a>
                          | <a href=!tops7.html>[T:field ops]</a>
                          | <a href=!tops8.html>[T:light weapons]</a>
                          | <a href=!tops9.html>[T:heavy weapons (soldiers)]</a>
                          | <a href=!tops10.html>[T:covert ops]</a>
                          | <a href=!tops11.html>[T:objectives]</a>",
                        mod_tops( "[T:top scores in single game]", SORT => $c || 3 ),
                        $skills_totals,
                        );
  }

for my $c ( '', 3..9 )
  {
  html_save( "wep$c",   "[T:sort by]:
                            <a href=!wep3.html>[T:Shots]</a>
                          | <a href=!wep4.html>[T:Hits]</a>
                          | <a href=!wep5.html>[T:Head]</a>
                          | <a href=!wep6.html>[T:Kills]</a>
                          | <a href=!wep7.html>[T:Acc.]%</a>
                          | <a href=!wep8.html>[T:HeadAcc.]%</a>",
                        mod_weapons_totals( "[T:weapons totals]", SORT => $c || 6 ) );
  }

for my $w ( keys %WEAPON )
  {
  my $ww = lc $WEAPON{ $w };
  for my $c ( '', 3..9 )
    {
    html_save( "w_$ww$c", "[T:sort by]: 
                            <a href=!w_${ww}3.html>[T:Shots]</a>
                          | <a href=!w_${ww}4.html>[T:Hits]</a>
                          | <a href=!w_${ww}5.html>[T:Head]</a>
                          | <a href=!w_${ww}6.html>[T:Kills]</a>
                          | <a href=!w_${ww}7.html>[T:Deaths]</a>
                          | <a href=!w_${ww}8.html>[T:Acc.]%</a>
                          | <a href=!w_${ww}9.html>[T:HeadAcc.]%</a>",
                          # mod_weapons_usage( "[T:usage of weapon] $WEAPON{$w} [T:by clan]", $w, CLAN => 1, SORT => $c || 6),
                          mod_weapons_usage( "[T:top figures for weapon] $WEAPON{$w} [T:by player]", $w, CLAN => 0, SORT => $c || 6 ) );
    }                    
  }                  

html_save( 'jerks',    mod_hash_stats( "[T:jerks ladder]", \%jerks, FLOOR => 16 ),
                       "<p><small><b>jerks</b> are players that play on the winning side when team XP differs more than $XPJERK_DIFF%</small>" );

html_save( 'p_',    'no info' ),

store( \%player, $ENV{ ETS_PL_STATS_FILE } ) if $ENV{ ETS_PL_STATS_FILE };

exit;

##############################################################################
##
##
##
##############################################################################

sub read_log_file
{
  my $time_now = time();
  
  my $time_base = 0;
  my $local_time = 0;
  my $last_local_time = 0;
  my $time = 0;
  my $running = 0;
  
  my $last_game_time;
  my $last_game_id;
  my %last_server;
  my %stats;    # game statistics, temporary used to collect data
  my %items;    # items collected/processed during the game, temporary used to collect data
  my %harvest;  # harvest awards, ammo and medkits
  my %snipe;    # usage of sniper weapons
  my %referees; # hold referees' names
  my $exit = 0; # keep status wether the level is over
  
  my $LAST_TIME = $LAST_DAYS * 24 * 60 * 60; # convert days into seconds
  
  print STDERR "processing log file: $LOG_FILE\n";
  
  open( my $i, $LOG_FILE ) or die "$0: cannot open log file: $LOG_FILE\n";
  while(<$i>)
    {
    DEBUG("line: $.");
    # print "line: $.\n" if $. % 10000 == 0;
    next if /^[\s\r\n]*$/o;
    s/<world>/*WORLD*/gio;
    s/^"?\s*(\d+):(\d+)(\.\d+)?\s*//o; # get time (^"? is for the buggy shrubet teamdamage logging)
#    use integer;
    $local_time = $1 * 60 + $2;
    if( $last_local_time > $local_time )
      {
      $time_base = $time_base + $last_local_time;
      }
    $last_local_time = $local_time;
    $time_base = $1 if /^TIME:(\d+)/o; # get time base
    DEBUG( "TIME:".localtime($time_base) ) if /^TIME:/;
    $time = $time_base + $local_time;
    next if $LAST_TIME > 0 and $time_now - $LAST_TIME > $time;
#    no integer;
    $minute = $time - $time % 60;
    my $time_str = scalar localtime( $time );
    $time_str =~ s/  / 0/o;
  
  #print STDERR "$time_str ($time) [$time_base:$local_time] $_";
  
    if( /^InitGame:\s*(.*)$/o )
      {
      $exit = 0;
      $running = 1;
      $last_game_time = $time;
      $last_game_id = strftime "%Y%m%d_%H%M%S", localtime $last_game_time;
      %last_server = split /\\/, "\\$1";
      DEBUG( "Initgame:".localtime($time));
      # detect new etpro version game
      if ( /etpro/o && /\\mod_version\\3/o ) {
          DEBUG( "etpro 3 mode detected");
          $MOD = 1;
      }
      next;
      }
    next unless $running;  
    if( /^ClientConnect: (\d+)/io )
      {
      #print STDERR "c: $1\n";
      next if exists $conn_time{ $1 };
      DEBUG( "ClientConnect-new:$1:$time");
      $conn_time{ $1 } = $time;
      next;
      }
    if( /^ClientDisconnect: (\d+)/io )
      {
      next unless exists $conn_time{ $1 };
      my $wasted = int( $time - $conn_time{ $1 } );
      DEBUG( "ClientDisconnect:$1:$wasted");
      delete $conn_time{ $1 };
      my $name = $client{ $1 }{ 'n' };
      #print STDERR "d: $1 ($name) $wasted\n";
      next if $name eq ''; # anonymous
      $time_waste{ $name } += $wasted;
      $time_waste{ get_clan( $name ) } += $wasted;
      next;
      }
    if( /^ShutdownGame:/o )
      {
      for my $k ( keys %conn_time )
        {
        my $wasted = int( $time - $conn_time{ $k } );
        my $name = $client{ $k }{ 'n' };
        next if $name eq '';
        $time_waste{ $name } += $wasted;
        $time_waste{ get_clan( $name ) } += $wasted;
        #print STDERR "d: $k ($name) $wasted\n";
        }
      %conn_time = ();  
      # next; # nadolu ima oshte edin handler za shutdown game
      }
    if( /^ClientUserinfoChanged: (\d+) (.+)/io or /^ClientUserinfoChangedGUID: (\d+) [0-9a-f]+ (.+)/io )
      {
      DEBUG( "$_" );
      # n\xwayBG\t\2\c\4\r\0\m\0000000\s\0000000\dn\chromosome\dr\0\w\10\lw\10\sw\41\mu\0\ref\0
      my $id = $1;
      my $data = $2;
      $client{ $id } = { split /\\/, $data };
      
      my ( $name, $color_name );
      $name = $color_name = $client{ $id }{ 'n' };
      $name =~ s/\^.//go; # clear colors etc.

      DEBUG( "ERROR:null name" ) if $name eq '';
      
      $client{ $1 }{ 'n' } = $name = $NAME_MAP->{ $name } if( $NAME_MAP->{ $name } );
      $nam{ $name }++;
      $nam{ get_clan( $name ) }++;
      
      $client_id{ $name } = $id;
      
      $NAM_COLOR{ $name } = $color_name if $name ne $color_name;
      
      $client{ $id }{ 'n' } = $name;
      $client{ $id }{ 'dn' } =~ s/\^.//go; # clear colors etc.
  
      my $dn     = $client{ $id }{ 'dn' };
      my $class  = $CLASS{ $client{ $id }{ 'c' } };
      my $side   = $SIDE{ $client{ $id }{ 't' } };
      my $weapon = $WEAPON{ $client{ $id }{ 'w' } };
      my $ref    = $client{ $id }{ 'ref' };
      
      my $info;
      $info .= "$time_str ^8$name has referee status" if $ref and ! $referees{ $id }++;
      push @trans, $info if $info;
      
      if( $dn )
        {
        $unif_taken{ $name }++;
        $unif_lost{ $dn }++;
        };

      if( $class_last{ $name } ne $class )
        {
        $class{ $name }{ $class }++;
        $class{ get_clan( $name ) }{ $class }++;
        $class_last{ $name } = $class;
        $global_class{ $class }++;
        $classes{ $class }{ $name }++;
        $classes{ $class }{ get_clan( $name ) }++;
        }
      if( $side_last{ $name } ne $side )
        {
        $side{ $name }{ $side }++;
        $side{ get_clan( $name ) }{ $side }++;
        $side_last{ $name } = $side;
        $global_side{ $side }++;
        $sides{ $side }{ $name }++;
        $sides{ $side }{ get_clan( $name ) }++;
        }

      next;
      }
    s/\^.//g; # clear colors etc. this is after ClientUserinfoChanged to preserve original names
    if( /^Item: (\d+) team_CTF_(red|blue)flag/o )
      {
      my $n = $client{ $1 }{ 'n' };
      my $f = uc $2;
      DEBUG( "$n CAPTURES/FLAGS/$f" );
      $items{ $n }{ "CAPTURES/FLAGS/$f" }++;
      $items{ $n }{ "TOTAL" }++;
      next;
      }
    if( /^Dynamite_Plant: +(\d+)/o )
      {
      my $n = $client{ $1 }{ 'n' };
      DEBUG( "$n DYNA/PLANT" );
      $items{ $n }{ 'DYNA/PLANT' }++;
      $items{ $n }{ "TOTAL" }++;
      next;
      }
    if( /^Dynamite_Diffuse: +(\d+)/o )
      {
      my $n = $client{ $1 }{ 'n' };
      DEBUG( "$n DYNA/DIFF" );
      $items{ $n }{ 'DYNA/DIFF' }++;
      $items{ $n }{ "TOTAL" }++;
      next;
      }
    if( /^Repair: (\d+)/o )
      {
      my $n = $client{ $1 }{ 'n' };
      DEBUG( "$n REPAIR" );
      $items{ $n }{ 'REPAIR' }++;
      $items{ $n }{ "TOTAL" }++;
      next;
      }
    if( /^([a-z]+_Pack): (\d+) (\d+)/io )
      {
      my $f = $client{ $2 }{ 'n' }; # from 
      my $t = $client{ $3 }{ 'n' }; # to
      $harvest{ uc "$1/DISPENSED" }{ $f }++;
      $harvest{ uc "$1/COLLECTED" }{ $t }++;
      $harvest{ uc "$1/DISPENSED" }{ get_clan( $f ) }++;
      $harvest{ uc "$1/COLLECTED" }{ get_clan( $t ) }++;
      }
    if( $exit and /WeaponStats(Dmg)?:\s*(.+)$/o )
      {
      my $ws = $2;
      DEBUG( "WeaponStats:$ws");
      my $data = parse_weaponstats( $ws, $last_game_id );
      $stats{ $data->{ 'PLAYER' } } = $data if $data;
      #my $map = uc "MAP:" . $last_server{ 'mapname' };
      #$nam{ $map }++;
      #parse_weaponstats( $ws, $last_game_id, PLAYER => $map );
      next;
      }
    if( /Exit:/o )
      {
      DEBUG( "EXIT");
      $last_server{ 'TIMELIMIT' } = /Timelimit/ ? 1 : 0;
      $exit = 1;
      }
    if( $exit and /^ShutdownGame/o )
      {
      DEBUG( "EXIT+SHUTDOWNGAME");
      # format items
      $items{ 'HEAD' }{ 'NAME' } = '<1>[100%][T:Player]';
      $items{ 'HEAD' }{ 'CAPTURES/FLAGS/RED' } = "<2>[>][T:Red Flag]";
      $items{ 'HEAD' }{ 'CAPTURES/FLAGS/BLUE' } = "<3>[>][T:Blue Flag]";
      $items{ 'HEAD' }{ 'DYNA/PLANT' } = "<4>[>][T:Dyna Plant]";
      $items{ 'HEAD' }{ 'DYNA/DIFF' } = "<5>[>][T:Dyna Diff]";
      $items{ 'HEAD' }{ 'REPAIR' } = "<6>[>][T:Repairs]";
      $items{ 'HEAD' }{ 'TOTAL' } = "<7>[>][T:Total]";
      
      $items{ 'FOOT' }{ 'NAME' } = '[>][T:Totals]:';
      $items{ 'FOOT' }{ 'CAPTURES/FLAGS/RED' } = '(SUM)/i';
      $items{ 'FOOT' }{ 'CAPTURES/FLAGS/BLUE' } = '(SUM)/i';
      $items{ 'FOOT' }{ 'DYNA/PLANT' } = '(SUM)/i';
      $items{ 'FOOT' }{ 'DYNA/DIFF' } = '(SUM)/i';
      $items{ 'FOOT' }{ 'REPAIR' } = '(SUM)/i';
      $items{ 'FOOT' }{ 'TOTAL' } = '(SUM)/i';
  
      my @players = keys %stats;
      my $pc = scalar @players;
      
      if( $pc >= $MIN_PLAYERS )
        {
        my $game_time = $time - $last_game_time;
        
        DEBUG( "ShutdownGame:$last_game_time:players=@players");
        push @games, { 'STATS' => { %stats },
                       'ITEMS' => { %items },
                       'TIME' => $last_game_time,
                       'ID' => $last_game_id,
                       'GAME_TIME' => $game_time,
                       'PLAYERS' => $pc,
                       'MAP' => $last_server{ 'mapname' },
                       'AXIS_XP' => $last_server{ 'AXIS_XP' },
                       'ALLIES_XP' => $last_server{ 'ALLIES_XP' },
                       'TIMELIMIT' => $last_server{ 'TIMELIMIT' },
                       'SNIPE' => { %snipe },
                       'TRANS' => [ @trans ],
                        };
        
        for my $p ( grep ! /^(HEAD|FOOT|COLS)$/, keys %items )
          {
          my $v;
          $v  = $items{ $p }{ 'TOTAL' };
          $v .= '.' . sprintf "%04d", $stats{ $p }{ 'SCORE' };
          # top objectives
          if( $v > $player{ $p }{ 'TOP_OBJ' } )
            {
            $player{ $p }{ 'TOP_OBJ' } = $v;
            $player{ $p }{ 'TOP_OBJ_GAME_ID' } = $last_game_id;
            }
          }
        
        for my $p ( keys %snipe )
          {
          for my $w ( keys %{ $snipe{ $p } } )
            {
            $top_snipe{ $p }{ $w } = $snipe{ $p }{ $w }
                if $snipe{ $p }{ $w } > $top_snipe{ $p }{ $w };
            }
          }
          
        for my $p ( keys %harvest )
          {
          for my $n ( keys %{ $harvest{ $p } } )
            {
            $top_harvest{ $p }{ $n } = $harvest{ $p }{ $n }
                if $harvest{ $p }{ $n } > $top_harvest{ $p }{ $n };
            }
          }
          
        }                
        
      for my $d ( keys %fsp_temp )
        {
        if( $fsp_temp{ $d } > $fsp{ $d } )
          {
          $fsp{ $d } = $fsp_temp{ $d };
          $fsp_game{ $d } = $last_game_id;
          $fsp_class{ $d } = $CLASS{ $client{ $client_id{ $d } }{ 'c' } };
          $fsp_time{ $d } = $time - $fsp_temp_time{ $d } if $fsp_temp_time{ $d } > 0 and $fsp_temp_time{ $d } > $last_game_time;
          $fsp_time{ $d } = 0 if $fsp_time{ $d } < 0;
          }
        delete $fsp_temp{ $d };
        }
        
      @trans = ();
      %stats = ();
      %snipe = ();
      %items = ();
      %harvest  = ();
      %referees = ();
      %fsp_temp = ();
      %fsp_temp_time = ();
      next;
      }  
    if( /red:(\d+) +blue:(\d+)/ )
      {
      $last_server{ 'AXIS_XP' } = $1;
      $last_server{ 'ALLIES_XP' } = $2;
      next;
      }
    if( /Kill: (\d+) (\d+) (\d+): (.+) killed (.+) by MOD_([A-Z_0-9]+)/io )
      {
      my $k = $NAME_MAP->{ $4 } || $4;
      my $d = $NAME_MAP->{ $5 } || $5;
      my $w = $6;
      
      $fsp_temp{ $k }++ if $k ne $d;
      $fsp_temp_time{ $k } = $time unless $fsp_temp_time{ $k };
      if( $fsp_temp{ $d } > $fsp{ $d } )
        {
        $fsp{ $d } = $fsp_temp{ $d };
        $fsp_game{ $d } = $last_game_id;
        $fsp_class{ $d } = $CLASS{ $client{ $client_id{ $d } }{ 'c' } };
        $fsp_time{ $d } = $time - $fsp_temp_time{ $d };
        $fsp_time{ $d } = 0 if $fsp_time{ $d } < 0;
        }
      delete $fsp_temp{ $d };
      delete $fsp_temp_time{ $d };
      
      next if $client{ $client_id{ $k } }{ 't' } eq $client{ $client_id{ $d } }{ 't' };
      
      # this is not entirely correct, though funny :)
      $kpm_temp{ $k }{ $minute }++;
      $kpm_temp{ get_clan( $k ) }{ $minute }++;
      $kpm_game{ $minute } = $last_game_id;
      
      # kills
      $kil{ $k }{ $d }++;
      $kil{ get_clan( $k ) }{ get_clan( $d ) }++;
      
      # deaths
      $ded{ $d }{ $k }++;
      $ded{ get_clan( $d ) }{ get_clan( $k ) }++;
      
      # weapon usage
      if( $w =~ /SCOPE$/ )
        {
        $snipe{ $k }{ $w }++;
        $snipe{ $k }{ 'ALL' }++;
        }
        
=pod    
      # get names...
      $nam{ $k }++;
      $nam{ $d }++;
      $nam{ get_clan( $k ) }++;
      $nam{ get_clan( $d ) }++;
=cut
      next;
      }
    if( /^say(team)?: (.+?): (.+)/io )
      {
      my $clr = $1 ? '^1' : '^4';
      
      DEBUG( "say$1: $2 $3");

      my $p = $2;
      my $cnt = $3 =~ /\S+/g;
      $noise{ $p } += $cnt;
      $noise{ get_clan( $p ) } += $cnt;
      
      push @trans, "$time_str $clr$_";
      next;
      }
    if ( /^ClientBegin: (\d+)/o )
      {
      DEBUG( "ClientBegin:".$1.":".$client{$1}{'n'});
      }
    #if( /^score: +(\d+) +ping: +(\d+) +client: (\d+) (.+)/ )
    #  {
    #  next;
    #  }
    #if( /?? end/start of game ??/ )
    #  {
    #  %class_last = ();
    #  %side_last = ();
    #  next;
    #  }  
    }
  close( $i );
  
  print STDERR "done (end virtual time is $time ". scalar(localtime($time))." )\n";
  1;
}

sub log_check_weaponstats
{
  open( my $i, $LOG_FILE ) or die "$0: cannot open log file: $LOG_FILE\n";
  while(<$i>)
    {
    if( /WeaponStats(Dmg)?:\s*(.+)$/o )
      {
      my $ws = $2;
      my $data = parse_weaponstats( $ws, $. );
      DEBUG( "$.", Dumper( $data ) );
      next;
      }
    }
}

##############################################################################
##
##
##
##############################################################################

sub read_con_file
{
  return unless $LOG_CON_FILE;
  my $pbc = 0;
  my $cnt = 0;
  print STDERR "processing console log file: $LOG_CON_FILE\n";
  open my $i, $LOG_CON_FILE;
  while(<$i>)
    {
    next if /^[\s\r\n]*$/o;
    s/\^.//g;
    
    next unless /^Userinfo: \\(.+)/;
    my %ui = split /\\/, $1;
    
    $cnt++;
    $pbc++ if $ui{'cl_punkbuster'};

    my $n = $ui{'name'};
    my $g = $ui{'cl_guid'};
    my $i = $ui{'ip'};
    
    $i =~ s/:\d+$//;
    
    $ip{ $i }{ $n }++;
    $ip_rev{ $n }{ $i }++;
    
    $guid{ $g }{ $n }++;
    $guid_rev{ $n }{ $g }++;
    }
  close $i;  

  while( my ( $n, $hr ) = each %ip_rev )
    {
    for my $i ( keys %$hr )
      {
      for my $nn ( keys %{ $ip{ $i } } )
        {
        $same_ip{ $n }{ $nn }++;
        }
      }
    }
  
  while( my ( $n, $hr ) = each %guid_rev )
    {
    for my $g ( keys %$hr )
      {
      next if $g eq 'unknown';
      for my $nn ( keys %{ $guid{ $g } } )
        {
        $same_guid{ $n }{ $nn }++;
        }
      }
    }
  
  print STDERR sprintf "%.2f%% of players are using PB\n", ( 100.0 * $pbc ) / $cnt if $cnt > 0;
  1;
}
  
##############################################################################
##
##
##
##############################################################################

sub mod_tops
{
  my $title = shift;
  my %opt = @_;
  my $clan = $opt{ 'CLAN' };
  
  my @data;

  my @p = keys %nam;
  @p = grep /^!/, @p if $clan;
  @p = grep ! /^!/, @p if ! $clan;
  
  push @data, [ 'HEAD', "[>5%]#", "[30%][T:Player/Clan]", 
                        "[>7%]XP",
                        map( { '[>7%]' . $SKILL_IMG{ $_ } } ( 0..6 ) ),
                        "[>7%][T:OBJ]", 
                         ];
  
  my $r = 0;
  for my $p ( @p )
    {
    my $pc = color_name( $p );
    
    my $og = $player{ $p }{ 'TOP_OBJ_GAME' };
    my $ogid = $player{ $p }{ 'TOP_OBJ_GAME_ID' };
    my $ob = $player{ $p }{ 'TOP_OBJ' };
    
    my $gid = $player{ $p }{ 'TOP_SCORE_GAME_ID' };
    my $xp  = $player{ $p }{ 'TOP_SCORE' };
    
    my @sk = map( { $player{ $p }{ 'TOP_SKILL' }{ $_ } } ( 0..6 ) );
    my @sg = map( { $player{ $p }{ 'TOP_SKILL_GAME_ID' }{ $_ } } ( 0..6 ) );
    
    push @data, [ '', "(ROW)", "<a class=t href=!p_$href{$p}.html>$pc</a>", 
                               "$xp<a href=game_$gid\.html>*</a>",
                               map( { $sk[$_] > 0 ? "$sk[$_]<a href=game_$sg[$_].html>*</a>" : undef } ( 0..6 ) ),
                               $ob > 0 ? "$ob<a href=game_$ogid\.html>*</a>" : undef,
                               ];
    }
  
  return "<h3 class='ets'>$title</h3>" . html_table( \@data, SORT => $opt{ SORT }, FLOOR => $TOPS_FLOOR );
}

##############################################################################

sub mod_clan_members
{
  my $title = shift;
  my %opt = @_;
  my $clan = shift;
  
  my @data;

  my @pl = keys %{ $members{ $clan } };
  
  push @data, [ 'HEAD', "[20%][T:Player]", "[20%][T:Player]", "[20%][T:Player]", "[20%][T:Player]", "[20%][T:Player]" ];

  while( @pl )
    {
    my @r;
    for( 1..5 )
      {
      my $p = shift @pl;
      my $pc = color_name( $p );
      push @r, "<a class=t href=!p_$href{$p}.html>$pc</a>";
      }
    push @data, [ '', @r ];
    }
  
  return "<h3 class='ets'>$title</h3>" . html_table( \@data );
}

##############################################################################

sub mod_players
{
  my %opt = @_;
  my $clan = $opt{ 'CLAN' };

  my @data;

  my $text;
  
  #$text .= "<p>";
  $text .= $clan ? "<h3 class='ets'>[T:Clans]</h3>" : "<h3 class='ets'>[T:Players]</h3>";

  my @p = keys %nam;
  my @row;
  my $c;
  
  for my $p ( sort @p )
    {
    next if $clan and $p !~ /^!/;
    next if !$clan and $p =~ /^!/;

    if( $c++ % 5 == 0 )
      {
      push @data, [ '', @row ];
      @row = ();
      }
 
    my $c = get_clan( $p );

    my $target1 = $href{ $c };
    my $target2 = $href{ $p };

    $p = color_name( $p );
    $c = color_name( $c );

    if( $c eq '!' )
      {
      push @row, "[20%]&nbsp <a href=!p_$target2.html>$p</a>";
      }
    else
      {  
      push @row, "[20%]<a href=!p_$target1.html>&#169</a> <a href=!p_$target2.html>$p</a>";
      }
    }
  push( @row, '[20%]&nbsp;') for ( 0 .. 5 - @row - 1 );
  push @data, [ '', @row ] if @row;
  $text .= html_table( \@data, FLOOR => 1_000_000 );
  $text .= "\n\n\n\n";
  return $text;
}

##############################################################################

sub mod_player_clan_stats
{
  my %opt = @_;
  my $clan = $opt{ 'CLAN' };

  my @data;

  my $text;
  
  $text .= "<p>";
  $text .= $clan ? "<h2>Clans</h2>" : "<h2>Players</h2>";

  push @data, [ 'HEAD', "[>5%]#", "[15%]Clan", "[30%]Player", "[>10%i]Kills", "[>10%i]Deaths", "[>10%]K:D" ];
  if( $clan )
    {
    $data[-1][2] = "[15%]";
    $data[-1][3] = "[30%]Clan";
    }
  
  my @p = keys %nam;
  
  for my $p ( @p )
    {
    next if $clan and $p !~ /^!/;
    next if !$clan and $p =~ /^!/;

    my $k = 0;
    my $d = 0;
    
    #$k += $kil{ $p }{ $_ } for keys %{ $kil{ $p } };
    #$d += $ded{ $p }{ $_ } for keys %{ $ded{ $p } };

    $k += $player{ $p }{ 'WEAPONS_TOTALS' }{ $_ }{ 'K' } for keys %{ $player{ $p }{ 'WEAPONS_TOTALS' } };
    $d += $player{ $p }{ 'WEAPONS_TOTALS' }{ $_ }{ 'D' } for keys %{ $player{ $p }{ 'WEAPONS_TOTALS' } };
    
    my $r = $d > 0 ? sprintf "%.2f", $k / $d : 'n/a'; #'

    my $c = get_clan( $p );

    my $target1 = $href{ $c };
    my $target2 = $href{ $p };

    $p =~ s/>/&gt;/go;
    $p =~ s/</&lt;/go;

    $p = color_name( $p );
    $c = color_name( $c );
    push @data, [ '', '(ROW)', "<a class=t href=!p_$target1.html>$c</a>",
                               "<a class=t href=!p_$target2.html>$p</a>",
                               $k, $d, $r,
                               ];
    }
  push @data, [ 'FOOT', '', '', 'Totals:', '(SUM)/i', '(SUM)/i', '' ];
  $text .= html_table( \@data, SORT => $opt{ 'SORT' }, SORTA => $opt{ 'SORTA' }, FLOOR => $opt{ 'FLOOR' } );
  $text .= "\n\n\n\n";
  return $text;
}

##############################################################################

sub single_game_stats
{
  my $gr = shift; # game hash reference
  my %opt = @_;
  
  my $side = $opt{ 'SIDE' };
  my $type = $opt{ 'TYPE' };
  
  my $game = $gr->{ 'STATS' };
  
  my $text;
  
  #$text .= Dumper( $gr );
  #$text = "<pre>$text</pre>";
  
  my @data_w;
  my @data_d;
  my @data_s;

  push @data_w, [ 'HEAD', '[>1%]#', '[30%][T:Player]', '[8%][T:Side]', '[9%>i][T:Shots]', '[9%>i][T:Hits]', '[9%>i][T:Head]', '[9%>i][T:Kills]', '[9%>i][T:Deaths]', '[9%>p][T:Acc.]%', '[9%>p][T:HAcc.]%', ];
  push @data_d, [ 'HEAD', '[>1%]#', '[30%][T:Player]', '[8%][T:Side]', '[20%>i][T:Damage Given]', '[20%>i][T:Damage Received]', '[21%>i][T:Team Damage]', ];
  push @data_s, [ 'HEAD', '[>1%]#', '[30%][T:Player]', '[8%][T:Side]', map( { '[>7%i]' . $SKILL_IMG{ $_ } } ( 0..6 ) ), '[>12%i]SCORE' ];

  my @p = keys %$game;
  @p = grep { $game->{ $_ }{ 'SIDE' } eq 'AXIS' } @p if $side eq 'AXIS';
  @p = grep { $game->{ $_ }{ 'SIDE' } eq 'ALLIES' } @p if $side eq 'ALLIES';
  #@p = sort { $game->{ $a }{ 'SIDE' } cmp $game->{ $b }{ 'SIDE' } } @p;
  @p = sort { $game->{ $b }{ 'SIDE'  } cmp $game->{ $a }{ 'SIDE'  } ||
              $game->{ $b }{ 'SCORE' } <=> $game->{ $a }{ 'SCORE' } } @p;
  
  for my $p ( @p )
    {
    my $v = $game->{ $p };
    my $wt = $v->{ 'WEAPONS_TOTALS' };
    my $pc = color_name( $p );
    my $sc = color_name( $v->{ 'SIDE' } );
    push @data_w, [ '', '(ROW)',
                "[<]<a class=t href=!p_$href{$p}.html>$pc</a>", 
                "<a class=t href=!p_sides.html>$sc</a>",
                $wt->{ 'S' },
                $wt->{ 'H' },
                $wt->{ 'E' },
                $wt->{ 'K' },
                $wt->{ 'D' },
                $wt->{ 'HA' },
                $wt->{ 'EA' },
                ];

    if( $type eq 'DETAILS' )
      {
      for my $w ( sort keys %{ $v->{ 'WEAPONS' } } )
        {
        $wt = $v->{ 'WEAPONS' }{ $w };
        push @data_w, [ 'COMT', '(ROW)',
                    '[>]' . $WEAPON{ $w },
                    "<a class=t href=!p_sides.html>$sc</a>",
                    $wt->{ 'S' },
                    $wt->{ 'H' },
                    $wt->{ 'E' },
                    $wt->{ 'K' },
                    $wt->{ 'D' },
                    $wt->{ 'HA' },
                    $wt->{ 'EA' },
                    ];
        }
      }          
    push @data_d, [ '', '(ROW)',
                "<a class=t href=!p_$href{$p}.html>$pc</a>", 
                color_name( $v->{ 'SIDE' } ),
                $v->{ 'DAMAGE' }{ 'SENT' },
                $v->{ 'DAMAGE' }{ 'RECV' },
                $v->{ 'DAMAGE' }{ 'TEAM' },
                ];
    my @ss;
    push @ss, $v->{ 'SKILL' }{ $_ } for ( 0..6 );
    push @data_s, [ '', '(ROW)',
                "<a class=t href=!p_$href{$p}.html>$pc</a>", 
                color_name( $v->{ 'SIDE' } ),
                @ss,
                $v->{ 'SCORE' }
                ];
    }

  push @data_w, [ 'FOOT', '', '', '[>][T:Total]:', '(SUM)/i', '(SUM)/i', '(SUM)/i', '(SUM)/i', '(SUM)/i', '(AVE)/p', '(AVE)/p', ];
  push @data_d, [ 'FOOT', '', '', '[>][T:Total]:', '(SUM)/i', '(SUM)/i', '(SUM)/i', ];
  push @data_s, [ 'FOOT', '', '', '[>][T:Total]:', map { '(SUM)/i' } ( 0 .. 6 ), '(SUM)/i' ];
  
  $side = color_name( $side );
  $text .= html_table( \@data_w ) if $type eq 'SHOTS';
  $text .= html_table( \@data_d ) if $type eq 'DAMAGE';
  $text .= html_table( \@data_s ) if $type eq 'SKILLS';
  $text .= html_table( \@data_w ) if $type eq 'DETAILS';
  
  return $text;
}

sub single_game_transcription
{
  my $gr = shift; # game hash reference
  my %opt = @_;

  my $text;

  my @data_t;
  for( @{ $gr->{ 'TRANS' } } )
    {
    push @data_t, [ '', '(ROW)', color_name( $_ ) ];
    }
  $text .= "<h3 class='ets'>[T:Transcription]</h3>" . html_table( \@data_t, FLOOR => 1_000_000 );
  
  return $text;
}

#----------------------------------------------------------------------------

sub mod_top_rank_stats
{
  my $title = shift;
  my $p = shift; # player
  my %opt = @_;
  
  return undef unless $player{ $p };
  print STDERR "$p\n" if $p =~ /^MAP:/;  
  
  my @data_s;
  
  push @data_s, [ 'HEAD', '[<40%][T:Rank]', '[<][T:In which game]' ];

  my $tr =  $RANK{ $player{ $p }{ 'TOP_RANK' } };
  my $trg = $player{ $p }{ 'TOP_RANK_GAME_ID' };
  my $des = $games{ $trg }{ 'DES' };
  push @data_s, [ '', $tr, 
                    "<a href=game_$trg\.html>$des</a>"
                    ];
  #push @data_s, [ 'FOOT', '', '' ];

  return "<h3 class='ets'>$title</h3>" . html_table( \@data_s );
}

#----------------------------------------------------------------------------

sub mod_top_scores_stats
{
  my $title = shift;
  my $p = shift; # player
  my %opt = @_;
  
  return undef unless $player{ $p };
  print STDERR "$p\n" if $p =~ /^MAP:/;  
  
  my @data_s;
  
  push @data_s, [ 'HEAD', '[>5%]#', '[<40%][T:Skill]', '[>10%i][T:Top Score]', '[<][T:In which game]' ];
  
  for my $s ( sort { $player{ $p }{ 'SKILL' }{ $b } <=> $player{ $p }{ 'SKILL' }{ $a } } 0..6 )
    {
    my $sc = $player{ $p }{ 'TOP_SKILL' }{ $s };
    next unless $sc > 0;
    my $gid = $player{ $p }{ 'TOP_SKILL_GAME_ID' }{ $s };
    my $des = $games{ $gid }{ 'DES' };
    push @data_s, [ '', '(ROW)', $SKILL_IMG{ $s } . " " . $SKILL{ $s }, 
                    $sc,
                    "<a href=game_$gid\.html>$des</a>"
                    ];
    }
  my $tot;
  $tot .= $SKILL_IMG{ $_ } for ( 0..6 );
  push @data_s, [ 'FOOT', '', "$tot TOTAL XP", 
                  $player{ $p }{ 'TOP_SCORE' },
                  ''
                  ];
  
  #push @data_s, [ 'FOOT', '', '', '' ];

  return "<h3 class='ets'>$title</h3>" . html_table( \@data_s );
}

#----------------------------------------------------------------------------

sub mod_skills_totals
{
  my $title = shift;
  my %opt = @_;
  
  my @data_s;
  
  push @data_s, [ 'HEAD', '[>5%]#', '[<][T:Skill]', '[>20%i][T:Score]' ];
  
  for my $s ( sort { $skills{ $b } <=> $skills{ $a } } keys %skills )
    {
    push @data_s, [ '', '(ROW)', $SKILL_IMG{ $s } . " " . $SKILL{ $s }, $skills{ $s } ];
    }
  
  my $tot;
  $tot .= $SKILL_IMG{ $_ } for ( 0..6 );
  push @data_s, [ 'FOOT', '', "[<]$tot [T:TOTAL] XP", '(SUM)/i' ];

  return "<h3 class='ets'>$title</h3>" . html_table( \@data_s );
}

#----------------------------------------------------------------------------

sub mod_player_weapons_stats
{
  my $title = shift;
  my $p = shift; # player
  my %opt = @_;
  
  return undef unless $player{ $p };
  
  my @data_w;
  
  push @data_w, [ 'HEAD', '[>5%]#', '[40%][T:Weapon]', '[>i][T:Shots]', '[>i][T:Hits]', '[>i][T:Head]', '[>i][T:Kills]', '[>i][T:Deaths]', '[>][T:K:D]', '[>p][T:Acc.]%', '[>p][T:HeadAcc.]%', ];
  my $tkills  = 0;
  my $tdeaths = 0;  
  for my $w ( sort { $player{ $p }{ 'TOP_WEAPONS' }{ $b }{ 'K' } <=> $player{ $p }{ 'TOP_WEAPONS' }{ $a }{ 'K' } } keys %{ $player{ $p }{ 'TOP_WEAPONS' } } )
    {
    my $wt = $player{ $p }{ 'WEAPONS_TOTALS' }{ $w };
    $wt->{ 'HA' } = $wt->{ 'S' } > 0 ? ( 100 * $wt->{ 'H' } ) / $wt->{ 'S' } : 'n/a';
    $wt->{ 'EA' } = $wt->{ 'S' } > 0 ? ( 100 * $wt->{ 'E' } ) / $wt->{ 'S' } : 'n/a';
    my $kdr = $wt->{ 'D' } > 0 ? sprintf( "%.2f", $wt->{ 'K' } / $wt->{ 'D' } ) : 'n/a'; 
    my $wn = $WEAPON{ $w };
    my $ww = lc $wn;
    push @data_w, [ '', '(ROW)',
                "<a href=!w_$ww.html>$wn</a>",
                $wt->{ 'S' },
                $wt->{ 'H' },
                $wt->{ 'E' },
                $wt->{ 'K' },
                $wt->{ 'D' },
                $kdr,
                $wt->{ 'HA' },
                $wt->{ 'EA' },
                ];
    $tkills  += $wt->{ 'K' };
    $tdeaths += $wt->{ 'D' };
    }
  my $tkdr = $tdeaths > 0 ? sprintf("%.2f", ($tkills / $tdeaths)) : 'n/a';
  push @data_w, [ 'FOOT', '', '[>][T:Total]:', '(SUM)/i', '(SUM)/i', '(SUM)/i', '(SUM)/i', '(SUM)/i', $tkdr, '(AVE)/p', '(AVE)/p', ];
  
  return "<h3 class='ets'>$title</h3>" . html_table( \@data_w, SORT => 6 );
}

#----------------------------------------------------------------------------

sub mod_weapons_usage
{
  my $title = shift;
  my $w = shift; # weapon
  my %opt = @_;

  my $clan = $opt{ 'CLAN' };
  
  my $ww = lc $WEAPON{ $w };
  
  my @data_w;
  
  push @data_w, [ 'HEAD', '[>5%]#', '[40%][T:Player/Clan]', "[>i][T:Shots]", "[>i][T:Hits]", "[>i][T:Head]", "[>i][T:Kills]", "[>i][T:Deaths]", "[>p][T:Acc.]%", "[>p][T:HeadAcc.]%", ];
  #for my $p ( sort { $player{ $b }{ 'WEAPONS' }{ $w }{ 'K' } <=> $player{ $a }{ 'WEAPONS' }{ $w }{ 'K' } } keys %player )
  for my $p ( keys %player )
    {
    next if $clan and $p !~ /^!/;
    next if !$clan and $p =~ /^!/;

    my $wt  = $player{ $p }{ 'TOP_WEAPONS' }{ $w };
    my $gid = $player{ $p }{ 'TOP_WEAPONS_GAME_ID' }{ $w }; 
    next if $wt->{ 'S' } == 0;
#    eval 
#      {
#      $wt->{ 'HA' } = ( 100 * $wt->{ 'H' } ) / $wt->{ 'S' };
#      $wt->{ 'EA' } = ( 100 * $wt->{ 'E' } ) / $wt->{ 'S' };
#      };
    my $pc = color_name( $p );
    push @data_w, [ '', '(ROW)',
                "<a class=t href=!p_$href{$p}.html>$pc</a>", 
                $wt->{ 'S' }  . "|<a href=game_$gid->{S}\.html>*</a>",
                $wt->{ 'H' }  . "|<a href=game_$gid->{H}\.html>*</a>",
                $wt->{ 'E' }  . "|<a href=game_$gid->{E}\.html>*</a>",
                $wt->{ 'K' }  . "|<a href=game_$gid->{K}\.html>*</a>",
                $wt->{ 'D' }  . "|<a href=game_$gid->{D}\.html>*</a>",
                $wt->{ 'HA' } . "|<a href=game_$gid->{HA}\.html>*</a>",
                $wt->{ 'EA' } . "|<a href=game_$gid->{EA}\.html>*</a>",
                ];
    }
    
  push @data_w, [ 'FOOT', '', '[>]+[T:Total]:', '(SUM)/i', '(SUM)/i', '(SUM)/i', '(SUM)/i', '(SUM)/i', '(AVE)/p', '(AVE)/p', ];
  
  return "<h3 class='ets'>$title</h3>" . html_table( \@data_w, SORT => $opt{ 'SORT' } );
}

#----------------------------------------------------------------------------

sub mod_weapons_totals
{
  my $title = shift;
  my %opt = @_;
  
  my @data_w;
  
  push @data_w, [ 'HEAD', '[>5%]#', '[40%][T:Weapon]', '[>i][T:Shots]', '[>i][T:Hits]', '[>i][T:Head]', '[>i][T:Kills]', '[>p][T:Acc.]%', '[>p][T:HeadAcc.]%', ];
  
  for my $w ( keys %weapons )
    {
    my $wt = $weapons{ $w };
    my $s = $wt->{ 'S' };
    if( $s > 0 )
      {
      $wt->{ 'HA' } = ( 100 * $wt->{ 'H' } ) / $wt->{ 'S' };
      $wt->{ 'EA' } = ( 100 * $wt->{ 'E' } ) / $wt->{ 'S' };
      };
    my $wn = $WEAPON{ $w };
    my $ww = lc $wn;
    push @data_w, [ '', '(ROW)',
                "<a href=!w_$ww.html>$wn</a>",
                $wt->{ 'S' },
                $wt->{ 'H' },
                $wt->{ 'E' },
                $wt->{ 'K' },
                $wt->{ 'HA' },
                $wt->{ 'EA' },
                ];
    }

  push @data_w, [ 'FOOT', '', '[>][T:Total]:', '(SUM)/i', '(SUM)/i', '(SUM)/i', '(SUM)/i', '(AVE)/p', '(AVE)/p', ];
  
  return "<h3 class='ets'>$title</h3>" . html_table( \@data_w, SORT => $opt{ 'SORT' } );
}

##############################################################################

my %seen_weaponstats = ();
sub parse_weaponstats
{
  my $ws = shift;
  my $game_id   = shift; # to skip seen weponstats per game
  my %opt = @_;
  # WeaponStats: 
  # 2 1 3145756 0 0 0 1 0 3 14 0 0 0 0 0 0 1 0 0 0 0 1 0 3 8 1 0 1 238 472 0 65 9 5
  my @ws = split /\s+/, $ws;
  
  my %data;
  
  $data{ 'CLIENT' } = shift @ws;
  $data{ 'PLAYER' } = $client{ $data{ 'CLIENT' } }{ 'n' };
  $data{ 'SIDE'   } = $SIDE{ $client{ $data{ 'CLIENT' } }{ 't' } };
  $data{ 'CLASS'  } = $CLASS{ $client{ $data{ 'CLIENT' } }{ 'c' } };
  $data{ 'CARRY' } = shift @ws; # 0 = first round, 1 == carry, i.e. second or next round

  $data{ 'PLAYER' } = $opt{ 'PLAYER' } if $opt{ 'PLAYER' };

  my $p = $data{ 'PLAYER' };

  next if $seen_weaponstats{ "$game_id:$ws:$p" }++;
  
  DEBUG( "parse_weaponstats:$p");
  DEBUG( "$ws");

  # parse all weapon stats
  my @wep = reverse split //, sprintf '%b', shift @ws;
  my $wc = -1; # weapon counter
  for( @wep )
    {
    $wc++;
    next unless $_;
    
    my $h = $data{ 'WEAPONS' }{ $wc }{ 'H' } = shift @ws;
    my $s = $data{ 'WEAPONS' }{ $wc }{ 'S' } = shift @ws;
            $data{ 'WEAPONS' }{ $wc }{ 'K' } = shift @ws;
            $data{ 'WEAPONS' }{ $wc }{ 'D' } = shift @ws;
    my $e = $data{ 'WEAPONS' }{ $wc }{ 'E' } = shift @ws;
    if ( $s > 0 )
      {
      $data{ 'WEAPONS' }{ $wc }{ 'HA' } = ( 100 * $h ) / $s;
      $data{ 'WEAPONS' }{ $wc }{ 'EA' } = ( 100 * $e ) / $s;
      }
    }
  # summarize parsed weapon stats to total
  for my $w ( keys %{ $data{ 'WEAPONS' } } )
    {
    for my $a ( qw( S H K D E HA EA ) )
      {
      my $wwa = $data{ 'WEAPONS' }{ $w }{ $a };
      $data{ 'WEAPONS_TOTALS' }{ $a } += $wwa;
      $player{ $p }{ 'WEAPONS_TOTALS' }{ $w }{ $a } += $wwa;
      $weapons{ $w }{ $a } += $wwa;
      
      if( $player{ $p }{ 'TOP_WEAPONS' }{ $w }{ $a } < $wwa )
        {
        $player{ $p }{ 'TOP_WEAPONS' }{ $w }{ $a } = $wwa;
        $player{ $p }{ 'TOP_WEAPONS_GAME_ID' }{ $w }{ $a } = $game_id;
        }
      }
    }  
  my $s = $data{ 'WEAPONS_TOTALS' }{ 'S' };
  if ( $s > 0 )
    {
    $data{ 'WEAPONS_TOTALS' }{ 'HA' } = ( 100 * $data{ 'WEAPONS_TOTALS' }{ 'H' } ) / $s;
    $data{ 'WEAPONS_TOTALS' }{ 'EA' } = ( 100 * $data{ 'WEAPONS_TOTALS' }{ 'E' } ) / $s;
    }
           $data{ 'DAMAGE' }{ 'SENT' } = shift @ws;  
           $data{ 'DAMAGE' }{ 'RECV' } = shift @ws;  
  my $td = $data{ 'DAMAGE' }{ 'TEAM' } = shift @ws; # given in ETpro 3
  if ( $MOD == 1 )
    {
        # handle ETpro 3 appended values
        shift @ws; # team damage received in ETpro 3
        shift @ws; # mgibs? in ETpro 3
    }
  
  my $cp = get_clan( $p );
  $top_td{ $p }  = $td if $td > $top_td{ $p };
  $top_td{ $cp } = $td if $td > $top_td{ $cp };

  # parse skills
  my @ski = reverse split //, sprintf '%b', shift @ws;
  my $sc = -1; # skill counter
  my %skill_snap;
  for( @ski )
    {
    $sc++;
    next unless $_;
    my $sk = shift @ws;
    
    $data{ 'SKILL' }{ $sc } = $sk; # each skill for this game (xp)
    $data{ 'SCORE' } += $sk; # score for this game (xp sum)
    
    # skill totals
    $skills{ $sc } += $sk;

    # skill snapshot for this game (used for rank)
    $skill_snap{ $sc } = $sk;

    # top skills
    if( $sk > $player{ $p }{ 'TOP_SKILL' }{ $sc } )
      {
      $player{ $p }{ 'TOP_SKILL' }{ $sc } = $sk;
      $player{ $p }{ 'TOP_SKILL_GAME_ID' }{ $sc } = $game_id;
      }
    
    DEBUG( sprintf( "%010d:%s:%s:%s", $sk, $SKILL{ $sc }, $game_id, $p ) );
    }
  DEBUG( sprintf( "%010d:%s:%s:%s", $data{ 'SCORE' }, 'TOTAL SCORE', $game_id, $p ) );

  # compute rank
  my $star_4 = 0; 
  my $star_3 = 0; 
  my $star_2 = 0; 
  my $star_1 = 0; 
  while( my ( $k, $v ) = each %skill_snap ) 
    {
    if( $v >= 140 ) { $star_4++; next; }
    if( $v >=  90 ) { $star_3++; next; }
    if( $v >=  50 ) { $star_2++; next; }
    if( $v >=  30 ) { $star_1++; next; }
    }
  my $rank = 0;
  if( $star_1  > 0) { $rank = 1 };
  if( $star_2  > 0) { $rank = 2 };
  if( $star_3  > 0) { $rank = 3 };
  if( $star_4 == 1) { $rank = 4 };
  if( $star_4 == 2) { $rank = 5 };
  if( $star_4 == 3) { $rank = 6 };
  if( $star_4 == 4) { $rank = 7 };
  if( $star_4 == 5) { $rank = 8 };
  if( $star_4 == 6) { $rank = 9 };
  if( $star_4 == 7) { $rank = 10 };
  
  if( $rank > $player{ $data{ 'PLAYER' } }{ 'TOP_RANK' } )
    {
    $player{ $p }{ 'TOP_RANK' } = $rank;
    $player{ $p }{ 'TOP_RANK_GAME_ID' } = $game_id;
    }

  # top scores
  if( $data{ 'SCORE' } > $player{ $data{ 'PLAYER' } }{ 'TOP_SCORE' } )
    {
    $player{ $p }{ 'TOP_SCORE' } = $data{ 'SCORE' };
    $player{ $p }{ 'TOP_SCORE_GAME_ID' } = $game_id;
    }

  # top ranks
  my $rankxp = ($rank * 100000) + $data{ 'SCORE' }; 
  if( $rankxp > $top_ranks{ $p }{ 'RANKXP' } )
    {
    $top_ranks{ $p }{ 'RANKXP' } = $rankxp;
    $top_ranks{ $p }{ 'GAME_ID' } = $game_id;
    }

  return $data{ 'SCORE' } > 0 ? \%data : undef; # ako nqma tochki, ne e igral :)
}

#----------------------------------------------------------------------------

# FIXME: merge KPM and FSP below!!!

sub mod_kpm_stats
{
  my $title = shift;
  my %opt = @_;
  my $clan = $opt{ 'CLAN' };
  
  my @data;
  
  push @data, [ 'HEAD', '[>5%]#', '[<40%][T:Player]', '[>10%i][T:Top Kills]', '[<][T:In which game]' ];
  
  for my $p ( sort { $kpm{ $b } <=> $kpm{ $a } } keys %kpm )
    {
    next if $clan and $p !~ /^!/;
    next if !$clan and $p =~ /^!/;
    
    my $pc  = color_name( $p );
    my $k   = $kpm{ $p };
    my $gid  = $kpm_game{ $p };
    my $des = $games{ $gid }{ 'DES' };
    
    push @data, [ '', 
                  '(ROW)',
                  "[<]<a class=t href=!p_$href{$p}.html>$pc</a>", 
                  $k,
                  "<a href=game_$gid\.html>$des</a>"
                  ];
    }

  return "<h3 class='ets'>$title</h3>" . html_table( \@data, FLOOR => $opt{FLOOR} );
}

sub mod_fsp_stats
{
  my $title = shift;
  my %opt = @_;
  my $clan  = $opt{ 'CLAN' };
  my $class = $opt{ 'CLASS' };
  
  my @data;
  
  push @data, [ 'HEAD', '[>5%]#', '[<40%][T:Player]', '[<10%][T:Class]', '[>10%i][T:Frags]', '[>10%][T:Duration]', '[<][T:In which game]' ];
  
  my @p =  keys %fsp;
  
  @p = grep { $fsp_class{ $_ } eq $class } @p if $class;
  
  for my $p ( @p )
    {
    next if $clan and $p !~ /^!/;
    next if !$clan and $p =~ /^!/;
    
    my $pc   = color_name( $p );
    my $k    = $fsp{ $p };
    my $gid  = $fsp_game{ $p };
    my $cl   = $fsp_class{ $p };
    my $des  = $games{ $gid }{ 'DES' };
    my $time = $fsp_time{ $p };
    
    $time = sprintf "%3d:%02d", int( $time / 60 ), $time % 60;
    
    push @data, [ '', 
                  '(ROW)',
                  "[<]<a class=t href=!p_$href{$p}.html>$pc</a>", 
                  $cl,
                  $k,
                  $time,
                  "<a href=game_$gid\.html>$des</a>"
                  ];
    }

  $title = "$class $title" if $class;
  return "<h3 class='ets'>$title</h3>" . html_table( \@data, SORT => 4, FLOOR => $opt{ FLOOR } );
}

#----------------------------------------------------------------------------

sub mod_hash_stats_2d
{
  my $title = shift;
  my $hr    = shift;
  my %opt   = @_;
  my $text;

  return '' unless $hr;
  return '' unless %$hr;

  $hr->{ 'HEAD' } or die "mod_hash_stats_2d: no HEAD info";
  my $head = { %{ $hr->{ 'HEAD' } } } || {} if $hr->{ 'HEAD' };
  my $foot = { %{ $hr->{ 'FOOT' } } } || {} if $hr->{ 'FOOT' };
  my $cols = { %{ $hr->{ 'COLS' } } } || {} if $hr->{ 'COLS' };
  my @cols = keys %$head;
  while( my ( $k, $v ) = each %$head )
    {
    next unless $v =~ s/^<(\d+)>//;
    $cols->{ $k } = $1;
    $head->{ $k } = $v;
    }
  @cols = sort { $cols->{ $a } <=> $cols->{ $b } } @cols;

  my $c = 1;
  $cols->{ $_ } = $c++ for @cols;

  my $text;
  my @data;
  my @temp;
  
  my @list = grep ! /^(HEAD|FOOT|COLS)$/, keys %$hr;
  
  return '' unless @list;
  
  @temp = ( 'HEAD' );
  push @temp, $head->{ $_ } for @cols;
  push @data, [ @temp ];
  
  for my $e ( @list )
    {
    @temp = ( '' );
    push @temp, $hr->{ $e }{ $_ } for @cols;
    push @data, [ @temp ];
    }

  if( $hr->{ 'FOOT' } )
    {
    @temp = ( 'FOOT' );
    push @temp, $foot->{ $_ } for @cols;
    push @data, [ @temp ];
    }

  $text .= "<h3 class='ets'>$title</h3>";
  $text .= html_table( \@data, 'SORT'  => $opt{ 'SORT' },
                               'SORTA' => $opt{ 'SORTA' },
                               'FLOOR' => $opt{ 'FLOOR' } );
  $text .= "\n\n\n\n";
  return $text;
}

#----------------------------------------------------------------------------

sub mod_kill_killed
{
  my $title = shift;
  my $p = shift; # player
  my %opt = @_;
  
  my @data;
  push @data, [ 'HEAD', "[>5%]#", "[25%][T:Killed]:", "[>10%][T:Times]", "[>10%]%",
                        "[>5%]#", "[25%][T:Killed by]:", "[>10%][T:Times]", "[>10%]%" ];

  my @killed = sort { $kil{ $p }{ $b } <=> $kil{ $p }{ $a } } keys %{ $kil{ $p } };
  my @killby = sort { $ded{ $p }{ $b } <=> $ded{ $p }{ $a } } keys %{ $ded{ $p } };
  
  my $sum_k = hash_sum( $kil{ $p } );
  my $sum_d = hash_sum( $ded{ $p } );
  
  my $c = 0;
  while(4)
    {
    my $k = shift @killed;
    my $d = shift @killby;
    
    my $kv = $kil{ $p }{ $k };
    my $dv = $ded{ $p }{ $d };
    
    my $kp = $sum_k > 0 ? ( 100 * $kv ) / $sum_k : 0;
    my $dp = $sum_d > 0 ? ( 100 * $dv ) / $sum_d : 0;
    
    my $kc = color_name( $k );
    my $dc = color_name( $d );
    
    push @data, [ '', '(ROW)', "<a class=t href=!p_$href{$k}.html>$kc</a>", $kv, "$kp/p",
                      '(ROW)', "<a class=t href=!p_$href{$d}.html>$dc</a>", $dv, "$dp/p" ];
    
    last unless @killed or @killby;
    last if ++$c == $FLOOR;
    }
    
  push @data, [ 'FOOT', '', '[>][T:Total]:', '(SUM)', '',
                        '', '[>][T:Total]:', '(SUM)', '' ];
  
  return "<h3 class='ets'>$title</h3>" . html_table( \@data, FLOOR => 16 );
}

#----------------------------------------------------------------------------

sub mod_games_for_player
{
  my $title = shift;
  my $p = shift; # player
  my %opt = @_;
  
  my @games_text;
  push @games_text, [ 'HEAD', 
                      '[>5%]#', 
                      '[15%][T:Map]',
                      '[20%][T:Game Started At]', 
                      '[>5%][T:Time]', 
                      '[>5%][T:IXP]', 
                      '[>5%][T:AXP]', 
                      '[5%][T:TLH]',
                      '[40%][T:Players]' ];

  for my $gr ( @games )
    {
    if( $p =~ /^!/ )
      { # clan
      my $in;
      for( keys %{ $gr->{ 'STATS' } } )
        {
        $in = 1 and last if get_clan( $_ ) eq $p;
        }
      next unless $in;
      }
    else
      { # player
      next unless $gr->{ 'STATS' }{ $p };
      }
    
    my $gid = $gr->{ 'ID' }; # game id
    my $ti  = $gr->{ 'TIME' };
    my $ma  = $gr->{ 'MAP' };
    my $gt  = $gr->{ 'GAME_TIME' };
    
    my $gts = sprintf "%dm%02ds", int( $gt / 60 ), int( $gt % 60 );
    
    my $tm = localtime( $ti );
    $tm =~ s/:\d\d / /; # remove seconds
    my $pl = sprintf "%02d", $gr->{ 'PLAYERS' };
    my $ww = $pl * 8;
    
    my $des = $gr->{ 'DES' } = "$ma $pl\[T:pl.] $tm";
    
    push @games_text, [ '', 
                        '(ROW)', 
                        $ma, 
                        "<a href=!game_$gid.html>$tm</a>&nbsp;(<a href=!game_$ti\_trans.html>T</a>)",
                        $gts,
                        $gr->{ 'AXIS_XP' },
                        $gr->{ 'ALLIES_XP' },
                        $gr->{ 'TIMELIMIT' } ? '[T:Yes]' : '[T:No]',
                        "$pl <img src=#wp.gif height=10 width=$ww>"
                      ];
    }
  
  return "<h3 class='ets'>$title</h3>" . html_table( \@games_text );
}

#----------------------------------------------------------------------------

sub mod_map_stats
{
  my $title = shift;
  my %opt = @_;
  
  my @games_text;
  push @games_text, [ 'HEAD', 
                      '[>5%]#', 
                      '[<45%][T:Map]',
                      '[>10%][T:Games]', 
                      '[>10%][T:Axis wins]', 
                      '[>10%][T:Allies wins]',
                      '[>10%][T:XP Bad Games]', 
                      '[>10%][T:XP Win Theory]'
                       ];
  my %maps;
  my $c;

  for my $gr ( @games )
    {
    my $m   = $gr->{ 'MAP' };
    my $tlh = $gr->{ 'TIMELIMIT' };
    my $ixp = $gr->{ 'AXIS_XP' };
    my $axp = $gr->{ 'ALLIES_XP' };
    my $pl  = $gr->{ 'PLAYERS' };
    
    next if $ixp < $WINS_MINXP;
    next if $axp < $WINS_MINXP;
    
    my $winner = uc get_winner( $m, $tlh );
    next unless $winner;
    $c++;
    
    $maps{ $m }{ 'TOTAL' }++;
    $maps{ $m }{ $winner }++;
    
    $maps{ $m }{ 'PPL' }{ $pl }{ $winner }++;
    
    next if $axp == $ixp;
    my $max = $axp > $ixp ? $axp : $ixp;
    my $dif = ( 100 * abs( $axp - $ixp ) ) / $max;
    next if $dif < $XPWINS_DIFF;
    $maps{ $m }{ 'XPTOTALS' }++;
    $maps{ $m }{ 'XPWINS' }++ if $axp > $ixp and $winner eq 'ALLIES';
    $maps{ $m }{ 'XPWINS' }++ if $axp < $ixp and $winner eq 'AXIS';
    # jerks stats, must be called just once!
    next if $dif < $XPJERK_DIFF;
    my $j_winner = 'NOBODY';
    $j_winner = 'ALLIES' if $axp > $ixp and $winner eq 'ALLIES';
    $j_winner = 'AXIS'   if $axp < $ixp and $winner eq 'AXIS';
    for my $p ( grep { $gr->{ 'STATS' }{ $_ }{ 'SIDE' } eq $j_winner } keys %{ $gr->{ 'STATS' } } )
      {
      $jerks{ $p } += $gr->{ 'STATS' }{ $p }{ 'SCORE' };
      }
    }
  return undef unless $c > 0;
  
  for my $m ( sort { $ORIGINAL_MAP{ $b } <=> $ORIGINAL_MAP{ $a } || $a cmp $b } keys %maps )
    {
    push @games_text, [ '', 
                        '(ROW)', 
                        $m, 
                        $maps{ $m }{ 'TOTAL' },
                        $maps{ $m }{ 'AXIS' },
                        $maps{ $m }{ 'ALLIES' },
                        $maps{ $m }{ 'XPTOTALS' },
                        $maps{ $m }{ 'XPWINS' } > 0 ? ( ( 100 * $maps{ $m }{ 'XPWINS' } ) / $maps{ $m }{ 'XPTOTALS' } ) . '/p' : 'n/a',
                      ];
    }

    push @games_text, [ 'FOOT', 
                        '', 
                        '[>][T:Totals:]', 
                        '(SUM)',
                        '(SUM)',
                        '(SUM)',
                        '(SUM)',
                        '(AVE)/p',
                      ];
  
  return "<h3 class='ets'>$title</h3>" . html_table( \@games_text );
}

sub mod_map_stats_ppl
{
  my $title = shift;
  my %opt = @_;

  my $slots = 8;
  
  my %maps;
  my $c;

  for my $gr ( @games )
    {
    my $m   = $gr->{ 'MAP' };
    my $tlh = $gr->{ 'TIMELIMIT' };
    my $ixp = $gr->{ 'AXIS_XP' };
    my $axp = $gr->{ 'ALLIES_XP' };
    my $pl  = $gr->{ 'PLAYERS' };
    
    $pl = int( $pl / $slots );
    
    next if $ixp < $WINS_MINXP;
    next if $axp < $WINS_MINXP;
    
    my $winner = uc get_winner( $m, $tlh );
    next unless $winner;
    $c++;
    
    $maps{ $m }{ $pl }{ 'TOTAL' }++;
    $maps{ $m }{ $pl }{ $winner }++;
    
    next if $axp == $ixp;
    my $max = $axp > $ixp ? $axp : $ixp;
    my $dif = ( 100 * abs( $axp - $ixp ) ) / $max;
    next if $dif < $XPWINS_DIFF;
    $maps{ $m }{ $pl }{ 'XPTOTALS' }++;
    $maps{ $m }{ $pl }{ 'XPWINS' }++ if $axp > $ixp and $winner eq 'ALLIES';
    $maps{ $m }{ $pl }{ 'XPWINS' }++ if $axp < $ixp and $winner eq 'AXIS';
    }
  return undef unless $c > 0;
  
  my $text;
  for my $m ( sort { $ORIGINAL_MAP{ $b } <=> $ORIGINAL_MAP{ $a } || $a cmp $b } keys %maps )
    {
    my @games_text;
    push @games_text, [ 'HEAD', 
                        '[>5%]#', 
                        '[<40%][T:Map]',
                        '[>5%][T:Players]',
                        '[>10%][T:Games]', 
                        '[>10%][T:Axis wins]', 
                        '[>10%][T:Allies wins]',
                        '[>10%][T:XP Bad Games]', 
                        '[>10%][T:XP Win Theory]'
                         ];
    for my $pl ( sort { $a <=> $b } keys %{ $maps{ $m } } )
      {
      my $min =   $pl       * $slots;
      my $max = ( $pl + 1 ) * $slots;
      push @games_text, [ '', 
                          '(ROW)', 
                          $m, 
                          "$min - $max",
                          $maps{ $m }{ $pl }{ 'TOTAL' },
                          $maps{ $m }{ $pl }{ 'AXIS' },
                          $maps{ $m }{ $pl }{ 'ALLIES' },
                          $maps{ $m }{ $pl }{ 'XPTOTALS' },
                          $maps{ $m }{ $pl }{ 'XPWINS' } > 0 ? ( ( 100 * $maps{ $m }{ $pl }{ 'XPWINS' } ) / $maps{ $m }{ $pl }{ 'XPTOTALS' } ) . '/p' : 'n/a',
                        ];
      }
    push @games_text, [ 'FOOT', 
                        '',
                        '[>][T:Totals:]',
                        '',
                        '(SUM)',
                        '(SUM)',
                        '(SUM)',
                        '(SUM)',
                        '(AVE)/p',
                      ];
    $text .= "<p>" . html_table( \@games_text );
    }

  
  return "<h3 class='ets'>$title</h3>" . $text;
}

#----------------------------------------------------------------------------


###TEST#######################################################################

=pod

Axis   HELLS BELLS       0   1   0  0   0   0     0   125    0      0
                       4 0   1   0  0   0   1    0 0  125    0      0 
                       
Allies ValBo             2   4   0  1  33  17   360   800   66     31                       
                       0 1 133657 0 8 0 0 0 6 9 1 0 0 14 28 1 0 0 0 2 0 0 0 0 4 0 0 0 0 0 0 4 0 360 800 66 19 8 20 3

+++++++++
WS WeaponStats: 2 1 3145756 0 0 0 1 0 3 14 0 0 0 0 0 0 1 0 0 0 0 1 0 3 8 1 0 1 238 472 0 65 9 5                       
Axis   [LUD]CADE   1   3   0  0  25   0   238   472    0     14 
               WS 2 1 
               3145756 (1100000000000000011100)
                         0  0 0 1 0 
                         3 14 0 0 0 
                         0  0 0 1 0 
                         0  0 0 1 0 
                 MP-40   3  8 1 0 1 
                 
                 238 472 0 
                 65 9 5                       
                 
Weapon     Acrcy Hits/Atts Kills Deaths Headshots
-------------------------------------------------
Colt     :                     0      1         0
MP-40    :  21.4    3/14       0      0         0
Thompson :                     0      1         0
Garand   :                     0      1         0
K43 Rifle:  37.5    3/8        1      0         1

Damage Given: 238     Team Damage: 0
Damage Recvd: 472

Rank: Schutze (14 XP)
Skills         Level/Points
---------------------------
Battle Sense   0 (9/20)
Covert Ops     0 (5/20)
                 
------------------------------------------------------------------------------

tova e po-skoro tehnicheska tema taka che ako na nqkoi ne mu e interesno da q 
propusne oshte sega

mai uspqh da razbera kakvo oznachava WeaponStats ot log-a, bih iskal da go 
post-na tuk v sluchai
che na nqkoi mu potrqbva ili mu e interesno

ta v loga nakraq na vsqka igra se poqvqva tova (t.e. podobni redove ):

WeaponStats: 2 1 3145756 0 0 0 1 0 3 14 0 0 0 0 0 0 1 0 0 0 0 1 0 3 8 1 0 1 238 472 0 65 9 5

i sega edno po edno:

2 -- nomer na client-a (player)
1 -- tova mai e za kolko rounds sa tezi danni
3145756 -- bitmap s izpolzvanite oryjiq (binarno e: 1100000000000000011100) t.e. 
           izpolzvani sa 5 oryjiq (colt,mp40,thompson,garand,k43) sledvat grupi 
           ot po 5 chisla za vsqko polzvano oryjie i 
           oznachavat: hits, shots, kills, deaths, headshots

t.e. gornite chisla predstavlqvat tova:

Weapon Acrcy Hits/Atts Kills Deaths Headshots
-------------------------------------------------
Colt : 0 1 0
MP-40 : 21.4 3/14 0 0 0
Thompson : 0 1 0
Garand : 0 1 0
K43 Rifle: 37.5 3/8 1 0 1

sledvashtite 3 chisla sa:

Damage Given: 238
Damage Recvd: 472
Team Damage: 0

sled tova pak ima bitmap na izpolzvanite abilities (clasove)
65 -- binarno e 1000001 i levelite za tezi abilities:

Skills Level/Points
---------------------------
Battle Sense 0 (9/20)
Covert Ops 0 (5/20)

Rank-a mai samo se sybira, t.e. e 14

voila

btw: thanx na Lg-Badluck che mi obyrna vnimanie na komandata /statsdump!

cheers! 

=cut

###EOF########################################################################

