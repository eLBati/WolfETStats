##############################################################################
#
#  ETS -- Wolfenstein: Enemy Territory Statistics
#  (c) Vladi Shabanski <cade@bis.bg> 2003
#  http://soul.datamax.bg/~cade/away/ets
#
#  Developed for play.evrocom.net server ET community
#  http://play.evrocom.net
#
#  This software is distributed under GPL license, see COPYING for details.
#
#  $Id: ets.pm,v 1.8 2005/05/23 22:19:18 cade Exp $
#
##############################################################################
package ets;
use FindBin;
use lib "$FindBin::Bin/ets_lib";
use Exporter;
use strict;

our @ISA    = qw( Exporter );
our @EXPORT = qw(
                DEBUG
                
                $LOG_FILE     
                $LOG_CON_FILE 
                $LOG_PB_FILE  
                $OUTPUT_DIR   
                $WEB_PREFIX   
                $WEB_DIR      
                $THEME        
                $LAST_DAYS    
                $MOTD_FILE    
                $SERVER_URL   
                $MIN_PLAYERS  
                $FLOOR        
                $TOPS_FLOOR   
                $SCORE_MIN
                $XPWINS_DIFF  
                $XPJERK_DIFF  
                $WINS_MINXP   
                
                %CLASS
                %SIDE
                %WEAPON
                %WEAPON_REV
                %SKILL
                %SKILL_IMG
                %RANK
                %GAMETYPE
                %COLOR
                
                %WIN
                %ORIGINAL_MAP
                get_winner
                
                %NAM_COLOR
                $NAME_MAP
                $CLAN_MAP
                $TRANSLATION
                
                $REVISION
                $ETS_VER 
                $CREDITS
                
                get_clan
                
                %href
                mod_hash_stats
                
                hash_max
                hash_sum
                time_fmt

                make_columns
                html_table
                html_save
                color_name
                escape_name
                
                load_file save_file load_hash save_hash
                );

### CONFIG ###################################################################

our $ROOT = $ENV{ 'ETS_LIB' } || "$FindBin::Bin/ets_lib";

our $LOG_FILE      = $ENV{ 'ETS_LOG_FILE' };
our $LOG_CON_FILE  = $ENV{ 'ETS_CON_FILE' };
our $LOG_PB_FILE   = $ENV{ 'ETS_PB_FILE' };
our $OUTPUT_DIR    = $ENV{ 'ETS_OUTPUT_DIR' };
our $WEB_PREFIX    = $ENV{ 'ETS_WEB_PREFIX' };
our $WEB_DIR       = $ENV{ 'ETS_WEB_DIR' } || '.';
our $THEME         = $ENV{ 'ETS_THEME' } || "ets-default";
our $LAST_DAYS     = $ENV{ 'ETS_LAST_DAYS' };
our $MOTD_FILE     = $ENV{ 'ETS_MOTD_FILE' };
our $SERVER_URL    = $ENV{ 'ETS_SERVER_URL' } || 'http://play.evrocom.net'; # this is credit line, please preserve it!
our $MIN_PLAYERS   = $ENV{ 'ETS_MIN_PLAYERS' } || 4;
our $FLOOR         = $ENV{ 'ETS_FLOOR' } || 50;
our $TOPS_FLOOR    = $ENV{ 'ETS_TOPS_FLOOR' } || 15; # maximum player count on top scores page
our $SCORE_MIN     = $ENV{ 'ETS_SCORE_MIN' } || 100; # minimum player score to generate statistics
our $XPWINS_DIFF   = $ENV{ 'ETS_XPWINS_DIFF' } || 20; # minimum difference for xp wins theory calculation
our $XPJERK_DIFF   = $ENV{ 'ETS_XPJERK_DIFF' } || 30; # minimum difference for xp jerk ladder
our $WINS_MINXP    = $ENV{ 'ETS_WINS_MINXP' } || 200; # minimum xp to calculate wins
our $HTML_INC      = $ENV{ 'ETS_HTML_INC' }; # html include directory
our $CLAN_MAP_ONLY = $ENV{ 'ETS_CLAN_MAP_ONLY' }; # use only clan map, no clan recognition


our @HTML_INC = ( split( /\s+/, $HTML_INC ), "$ROOT/html_inc" );

### DEBUGGING ################################################################

our $DEBUG = $ENV{ 'DEBUG' };

sub DEBUG { print STDERR "DEBUG:@_\n" if $DEBUG; };

DEBUG( "START" );

### ET STATICS ###############################################################

our $REVISION = '$Revision: 1.8 $';
our $ETS_VER = $1 if $REVISION =~ /([\d\.]+)/;
our $CREDITS = "<small><a href=http://cade.datamax.bg/away/ets><b>ETS $ETS_VER</b></a> by (c) <a href=mailto:cade\@bis.bg>Vladi Belperchinov-Shabanski &lt;cade\@bis.bg&gt;</a> 2003</small>";

our %CLASS = (
             0 => 'SOLDIER',
             1 => 'MEDIC',
             2 => 'ENGINEER',
             3 => 'FIELD_OPS',
             4 => 'COVERT_OPS',
            );
            
our %SIDE  = (
             0 => 'UNKNOWN',
             1 => 'AXIS',
             2 => 'ALLIES',
             3 => 'SPECTATORS',
            );            

our %WEAPON = (
             0 => 'KNIFE',
             1 => 'LUGER',
             2 => 'COLT',             #  8
             3 => 'MP40',             #  9
             4 => 'THOMPSON',         # 10
             5 => 'STEN',             # 11
             6 => 'FG42',             # 15
             7 => 'PANZERFAUST',
             8 => 'FLAMETHROWER',
             9 => 'GRENADE',
            10 => 'MORTAR',
            11 => 'DYNAMITE',         # 26
            12 => 'AIRSTRIKE',        # 28
            13 => 'ARTY',             # 30
            14 => 'SYRINGE',
            15 => 'SMOKECAN',
            16 => 'SATCHEL',
            17 => 'GRENADE_LAUNCHER', # 18
            18 => 'LANDMINE',         # 45
            19 => 'MOBILE_MG42',
            20 => 'GARAND',
            21 => 'KAR98'
            );
our %WEAPON_REV = reverse %WEAPON;            

our %SKILL = (
             0 => 'BATTLE SENSE',             
             1 => 'ENGINEERING   (ENGINEER)',             
             2 => 'FIRST AID     (MEDIC)',
             3 => 'SIGNALS       (FIELD OPS)',
             4 => 'LIGHT WEAPONS',
             5 => 'HEAVY WEAPONS (SOLDIER)',
             6 => 'COVERT OPS    (COVERT OPS)',
            );

our %SKILL_IMG = (
             0 => "<img src=#bs.gif border=0>",
             1 => "<img src=#en.gif border=0>",
             2 => "<img src=#fa.gif border=0>",
             3 => "<img src=#si.gif border=0>",
             4 => "<img src=#lw.gif border=0>",
             5 => "<img src=#hw.gif border=0>",
             6 => "<img src=#co.gif border=0>",
            );

our %RANK = (
             0 => 'Private',
             1 => 'Private First Class',
             2 => 'Corporal',
             3 => 'Sergeant',
             4 => 'Lieutenant',
             5 => 'Captain',
             6 => 'Major',
             7 => 'Colonel',
             8 => 'Brigadier General',
             9 => 'Lieutenant General',
             10 => 'General'
            );

our %GAMETYPE = (
             2 => 'Single Map Objective',
             3 => 'Stopwatch',
             4 => 'Campaign',
             5 => 'Last Man Standing',
            );
            
# thanx, furiozo :)
our %COLOR = (
            '1' => 'f70400',
            '2' => '02f702',
            '3' => 'fdf900',
            '4' => '0006f8',
            '5' => '00f6f3',
            '6' => 'f407f5',
            '7' => 'f9f9f9',
            '8' => 'ff7b06',
            '9' => '7c7d81',
            '0' => '000100',
            'q' => 'f70303',
            ')' => 'f70303',
            'w' => 'f4f6f1',
            'e' => '8100fd',
            'r' => '00f904',
            't' => '0005f4',
            'y' => '7b7d7a',
            'u' => '00faf6',
            'i' => 'fb0033',
            'o' => 'eff174',
            'p' => '060702',
            'a' => 'fd9534',
            's' => 'fbf904',
            'd' => '007dfe',
            'f' => '3795c8',
            '&' => '3795c8',
            'g' => 'c2fcc9',
            'h' => '066432',
            '(' => '066432',
            'j' => 'ad1c17',
            'k' => '9b3107',
            'l' => 'cf9834',
            ';' => 'c0bfc7',
            'z' => 'bcbdc2',
            'x' => 'f98000',
            'c' => '7b0484',
            'v' => 'f900f9',
            'b' => '037d7e',
            'n' => 'faf9c0',
            'm' => '9b9935',
            ',' => 'cf9a3a',
            '.' => 'f7f8b6',
            '/' => 'fbfc7c',
            '-' => '98972d',
            '=' => '7f7f00',
            '\\' => '007f03',
            '[' => 'bec0bb',
            ']' => '7f7c0b',
            '\'' => 'c5f9c8',
            '*' => 'ae181a',
            );

# color map customization
%COLOR = ( %COLOR, load_hash( $ENV{ 'ETS_COLOR_OVERRIDE' } ) );

### WIN/LOSE MAP #############################################################

# grep InitGame | perl -ne 'print "$1\n" if /mapname\\([^\\]+)/' | sort | uniq

# this map tells who is winner if time limit is reached, i.e. who defends the map

our %WIN = (
              '2hide'              => 'AXIS',
              'tc_base'            => 'AXIS',
              'apennines_b2'       => 'AXIS',
              'atlantic'           => 'AXIS',
              'base'               => '',
              'battery'            => 'AXIS',
              'bzz_drunk'          => '',
              'carnage2'           => 'AXIS',
              'etsbay'             => 'AXIS',
              'flughafen'          => '',
              'fueldump'           => 'AXIS',
              'goldrush'           => 'AXIS',
              'maiden_beta4'       => '',
              'mml_church_et_v1'   => '',
              'mp_sillyctf'        => '',
              'nightcrawlers'      => 'AXIS',
              'normandy_final'     => '',
              'oasis'              => 'AXIS',
              'venice'             => 'AXIS',
              'password2'          => 'AXIS',
              'radar'              => 'AXIS',
              'raiders_b2'         => 'AXIS',
              'railgun'            => 'ALLIES',
              'rhine'              => 'AXIS',
              'rhine2'             => 'AXIS',
              'rhine_bridge'       => 'AXIS',
              'supplydepot'        => 'AXIS',
              'supplydepot2'       => 'AXIS',
              'temple'             => 'AXIS',
              'temple2'            => 'AXIS',
              'temple3'            => 'AXIS',
              'temple_final'       => 'AXIS',
              'stalingrad'         => 'AXIS',
              'fun_beach'          => 'AXIS',
              'fun_beach_final'    => 'AXIS',
              'trainyard'          => '',
              'v2_base_fp'         => 'ALLIES',
              'v2base'             => 'ALLIES',
              'caen'               => 'ALLIES',
              '1944_beach'         => 'AXIS',
              'axislab_final'      => 'AXIS',
              'ammodepot'          => 'AXIS',
          );

our %ORIGINAL_MAP = (
              'battery'            => 1,
              'fueldump'           => 1,
              'goldrush'           => 1,
              'radar'              => 1,
              'railgun'            => 1,
              'oasis'              => 1,
          );

sub get_winner
{
  my $map = lc shift();
  my $tlh = shift() ? 1 : 0;
  return undef unless $WIN{ $map };
  return $WIN{ $map } if $tlh;
  return $WIN{ $map } eq 'AXIS' ? 'ALLIES' : 'AXIS';
}

### VARS ETC #################################################################

our %NAM_COLOR;
our $NAME_MAP;
our $CLAN_MAP;    
our $TRANSLATION; 

our %href;

### TABLE FORMATTING #########################################################

sub make_columns
{
  my $text;
  
  my $c = @_;
  my $p = $c > 0 ? int( 100 / @_ ) : 100;
  
  $text .= "<table cellspacing=5 width=100% class=etscolumns><tr><td width=p% valign=top>";
  $text .= join "</td><td width=$p% valign=top>", @_;
  $text .= "</td></tr></table>";
  
  return $text;
}

sub html_table_cmp
{
  my $aa = shift;
  my $bb = shift;
  my $ta = shift; # row type
  my $tb = shift; # row type
  my $sa = shift; # sort alpha
  
  return -1 if $ta eq 'HEAD';
  return  1 if $tb eq 'HEAD';
  return  1 if $ta eq 'FOOT';
  return -1 if $tb eq 'FOOT';
  
  $aa = $3 if $aa =~ /^(\[([^\]]+)\])?(.+)(\/([ip]))?$/o;
  $bb = $3 if $bb =~ /^(\[([^\]]+)\])?(.+)(\/([ip]))?$/o;
  
  if( ! $sa )
    {
    $aa = $1 if $aa =~ /^([\+\-\d\.]+)/;
    $bb = $1 if $bb =~ /^([\+\-\d\.]+)/;
    }
  
  return $sa ? $aa cmp $bb : $bb <=> $aa;
}

sub html_table
{
  my $ar = shift;
  my %opt = @_;
  
  my $text;
  $text .= "<table class=ets width=100% cellspacing=1 cellpadding=5>\n";
  my @or; # options row
  my @ft; # format type
  my $r = -1; # row
  
  my @ar = @$ar;
  
  my $floor = $opt{ 'FLOOR' } || $FLOOR;
  
  my $oc = $opt{ 'SORT' } || $opt{ 'SORTA' }; # sort/order column
  @ar = sort { html_table_cmp( $a->[$oc], $b->[$oc], $a->[0], $b->[0], $opt{ 'SORTA' } ) } @ar if $oc > 0;
  
  for my $rr ( @ar )
    {
    $r++ if $rr->[0] eq '';
    if( $floor > 0 )
      {
      next if $rr->[0] eq 'COMT' and $r >= $floor;
      next if $rr->[0] eq ''     and $r >= $floor;
      }
    my $c = -1; # column
    my $class = $r % 2 ? 'r1' : 'r2';
    @or = @$rr and next if $rr->[0] eq 'OPT';
    $class = 'hh' if $rr->[0] eq 'HEAD'; # header
    $class = 'ff' if $rr->[0] eq 'FOOT'; # footer
    $class = 'cc' if $rr->[0] eq 'COMT'; # comments
    $text .= "<tr class=$class>\n";
    for( @$rr )
      {
      my $d = $_;
      $c++;
      next if $c == 0;
      
      if( $d =~ s/^\[([^\]]+)\]//o )
        {
        my $p = $1; # params
        my $o; # opts
        $o .= " align=right" if $p =~ />/o;
        $o .= " width=$1"    if $p =~ /(\d+%)/o;
        $or[$c] = $o;
        $ft[$c] = lc $1 if $p =~ /([ip])$/io;
        #print STDERR "TABLE OPT: $p --> $o\n";
        #$text .= "TABLE OPT: $p --> $o<br>";
        }
      my $f;
      $f = $ft[$c] if $rr->[0] ne 'HEAD' and $rr->[0] ne 'FOOT';
      $f = lc $1 if $d =~ s/\/([ip])$//io; # [i]nt, [p]ercent
      $d = table_sum( $ar, $c ) if $d eq '(SUM)';
      $d = table_ave( $ar, $c ) if $d eq '(AVE)';
      $d = table_med( $ar, $c ) if $d eq '(MED)';

      my $cmt;
      if( $f eq 'i' or $f eq 'p' )
        {
        ( $d, $cmt ) = split /\|/, $d, 2;
        }
      
      $d = num_fmt( int $d ) if $f eq 'i';
      $d = $d > 0 ? sprintf "%.2f%%", $d : '' if $f eq 'p';

      $d = '' if $f eq 'i' and $d == 0;
      
      $d = $r + 1 if $d eq '(ROW)';
      $d = "<span class=hitext>$d</div>" if $oc > 1 and $c == $oc and ! $$rr[0];
      $text .= "<td class=etstd $or[$c]>$d$cmt</td>\n";
      }
    $text .= "</tr>\n";
    }
  $text .= "</table>\n";
  return $text;
}

sub table_sum
{
  my $ar = shift;
  my $col = shift;
  my $sum = 0;
  for my $rr ( @$ar )
    {
    next if $rr->[0] ne ''; # skip HEAD,FOOT
    $sum += $rr->[$col];
    }
  return $sum;
}

sub table_ave
{
  my $ar = shift;
  my $col = shift;
  my $sum = 0;
  my $cnt = 0;
  for my $rr ( @$ar )
    {
    next if $rr->[0] ne ''; # skip HEAD,FOOT
    $sum += $rr->[$col];
    $cnt++;
    }
  return $cnt > 0 ? $sum / $cnt : 0;
}

sub table_med
{
  my $ar = shift;
  my $col = shift;
  my @sum;
  for my $rr ( @$ar )
    {
    next if $rr->[0] ne ''; # skip HEAD,FOOT
    push @sum, $rr->[$col];
    }
  @sum = sort { $b <=> $a } @sum;  
  return $sum[ @sum / 2 ];
}

### FORMATTING ###############################################################

sub time_fmt
{
  my $data = shift;
  my $d = int($data / (24*60*60));
  my $h = int(($data % (24*60*60)) / (60*60));
  my $m = int(($data % (60*60)) / 60);        
  my $s = $data % 60;                 
  return sprintf "%6dd %02dh %02dm %02ds", $d, $h, $m, $s;
}

sub num_fmt
{
  my $s = shift;
  $s = reverse $s;
  1 while $s =~ s/(\d\d\d)(\d)([^']*)$/$1'$2$3/;
  $s = reverse $s;
}

### ETS ######################################################################

sub color_name
{
  my $s = shift;
  my $cs = $NAM_COLOR{ $s } || $s;
  # return $s unless $cs;
  my $c = $cs =~ s/\^(.)/"<font color=#" . $COLOR{ lc $1 } . ">"/gie;
  $cs .= "</font>" x $c;
  return "<span class=name>$cs</name>";
}

sub hash_max
{
  my $hr = shift;
  my $max_k = undef;
  my $max_v = undef;
  while( my ( $k, $v ) = each %$hr )
    {
    if( $max_v eq '' or $v > $max_v )
      {
      $max_k = $k;
      $max_v = $v;
      next;
      }
    }
  #print STDERR "$max_k, $max_v\n";
  return ( $max_k, $max_v );
}

sub hash_sum
{
  my $hr = shift;
  my $sum = 0;
  while( my ( $k, $v ) = each %$hr )
    {
    next if $k =~ /^!/;
    $sum += $v;
    }
  return $sum;
}

our %CLAN_CACHE;
sub get_clan
{
  my $s = shift;
  my $cc = $CLAN_CACHE{ $s };
  return $cc if $cc;
  return uc '!' . $CLAN_MAP->{ $s } if $CLAN_MAP->{ $s };
  return '!' if $CLAN_MAP_ONLY;
  my $c;
  $c = $1 if ! $c and $s =~ /^\[([^\]]+)\]/o;
  $c = $1 if ! $c and $s =~ /\[([^\]]+)\]$/o;
  $c = $1 if ! $c and $s =~ /^([A-Z]{2,6})[:\-\|]/io;
  $c = $1 if ! $c and $s =~ /^=(.+?)=/o;
  $c = $1 if ! $c and $s =~ /^-(.+?)-/o;
  $c = $1 if ! $c and $s =~ /^=\|(.+?)\|=/o;
  $c = $1 if ! $c and $s =~ /^-\|(.+?)\|-/o;
  $c = $1 if ! $c and $s =~ /^<(.+?)>/o;
  return $CLAN_CACHE{ $s } = uc "!$c";
}

sub escape_name
{
  my $s = shift; 
  $s =~ s/([^a-zA-Z0-9\-\_])/sprintf("%02X", ord($1))/ge;
  return $s;
}

### MODS #####################################################################

#----------------------------------------------------------------------------

sub mod_hash_stats
{
  my $title = shift;
  my $hr    = shift;
  my %opt   = @_;
  my $text;

  my $clan = $opt{ 'CLAN' };
  my $tfmt = $opt{ 'TIMEFMT' };
  my $head = $opt{ 'HEAD' };
  my $href_prefix = $opt{ 'HREF_PREFIX' } || 'p_';
  
  my $sum = hash_sum( $hr );
  
  my @data;
  
  $text .= "<p>";
  $text .= "<h3 class='ets'>$title</h3>";
  
  push @data, [ 'OPT', "width=05% align=right", "width=40%", "width=30% align=right", "width=25% align=right" ];
  if( $head )
    {
    push @data, [ 'HEAD', split /\s*,\s*/, $head ];
    }
  else
    {  
    push @data, [ 'HEAD', "[>5%]#", "[<55%][T:Name]", "[>20%][T:Value]", "[>20%][T:Percentage]" ];
    }
  
  my $row = 0;
  for my $k ( sort { $hr->{ $b } <=> $hr->{ $a } } keys %$hr )
    {
    next if $clan and $k !~ /^!/;
    next if !$clan and $k =~ /^!/;
    
    my $v = $hr->{ $k };
    my $p = $sum > 0 ? sprintf "%.2f%%", 100 * $v / $sum : 'n/a'; # '
    
    my $k_colors = $opt{ 'NO_COLORS' } ? $k : color_name( $k );
    if( $href{ $k } )
      {
      $k = "<a class=t href=!$href_prefix$href{$k}.html>$k_colors</a>";
      }
    else
      {
      $k = $k_colors;
      }  
    
    $p = 'n/a' if $opt{ 'NOP' };
      
    if ( $row < $FLOOR )
      {
      $row++;
      $v = time_fmt( $v ) if $tfmt;
      push @data, [ '', '(ROW)', $k, $v, $p ];
      }        
    }
  $sum = time_fmt( $sum ) if $tfmt;
  if( $opt{ 'NOP' } )
    {
    pop( @$_ ) for ( @data );
    }
  else
    {  
    push @data, [ 'FOOT', '', '[>][T:Total]:', $sum, '' ];
    }
  $text .= html_table( \@data, FLOOR => $opt{ FLOOR } );
  $text .= "\n\n\n\n";
  return $text;
}

### IO #######################################################################

sub html_inc_file
{
  my $name = lc shift;
  my $html;
  for( @HTML_INC )
    {
    my $f = "$_/$name.html";
    next unless -e $f;
    #DEBUG( "html_inc_file: $f" );
    $html = load_file( $f );
    last;
    }
  $html =~ s/\[\#(\S+)\]/html_inc_file( $1 )/ge;
  return $html;
}

sub html_save
{
  my $file = shift;
  $file = "$OUTPUT_DIR/$file.html";
  
  my %DATA = %ENV;
  
  $DATA{ 'CREDITS' } = $CREDITS;
  $DATA{ 'FLOOR' } = $FLOOR;
  $DATA{ 'THEME' } = $THEME;
  $DATA{ 'TEXT' } = join '', @_;
  $DATA{ 'TIME' } = scalar localtime();
  $DATA{ 'LAST_DAYS' } = "Note: Statistics data for last $LAST_DAYS days only is used.<br>";
  
  my $html = html_inc_file( 'index' );
  
  $html =~ s/\[\$(\S+)\]/$DATA{ $1 }/g;
  $html =~ s/href=!/href=$WEB_PREFIX/gio;
  $html =~ s/href=#/href=$WEB_DIR/gio;
  $html =~ s/src=#/src=$WEB_DIR\/$THEME\/img\//gio;
  $html =~ s/\[T\:([^\]]*)\]/$TRANSLATION->{ $1 }||$1/gie; # \: is to avoid get_trans.pl
  save_file( $file, $html ) or die "$0: cannot save html file: $file ($!)\n";
  #print STDERR "file $file written ok\n";
}

sub load_file
{
  my $file = shift;
  open( my $i, $file ) or return undef;
  local $/ = undef;
  my $s = <$i>;
  close $i;
  return $s;
}

sub save_file
{
  my $file = shift;
  open( my $o, ">$file" ) or return undef;
  print $o @_;
  close( $o );
  return 1;
}

sub load_hash
{
  my $file = shift;
  my %opt = @_;
  my %h;
  for( split( /[\n\r]+/, load_file( $file ) ) )
    {
    next unless /(.+?)(?<!\\)=(.*)/;
    my $k = $1;
    my $v = $2;
    $k =~ s/\\(.)/$1/go;
    $v =~ s/\\(.)/$1/go;
    $k = uc $k if $opt{ 'KEY_UC' };
    $k = lc $k if $opt{ 'KEY_LC' };
    $v = uc $v if $opt{ 'VAL_UC' };
    $v = lc $v if $opt{ 'VAL_LC' };
    $h{ $k } = $v;
    }
  return \%h;  
}

sub save_hash
{
  my $file = shift;
  my $hr = shift;
  open( my $o, ">$file" ) or return undef;
  while( my ( $k, $v ) = each %$hr )
    {
    $k =~ s/=/\\=/g;
    print $o "$k=$v\n";
    }
  close( $o );
  return 1;
}

##############################################################################
1;
### EOF ######################################################################

