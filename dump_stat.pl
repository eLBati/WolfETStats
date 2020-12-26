#!/usr/bin/perl
use Storable;
use Data::Dumper;
use strict;

my $pl = retrieve('pl_stats.store');
print "ok\n";
sleep(20);
print Dumper( $pl );

=pod

our %SKILL = (
             0 => 'BATTLE SENSE',             
             1 => 'ENGINEERING   (ENGINEER)',             
             2 => 'FIRST AID     (MEDIC)',
             3 => 'SIGNALS       (FIELD OPS)',
             4 => 'LIGHT WEAPONS',
             5 => 'HEAVY WEAPONS (SOLDIER)',
             6 => 'COVERT OPS    (COVERT OPS)',
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

$pl = {
          'Rangy' => {
                       'WEAPONS_TOTALS' => {
                                             # '3' is mp40, see above
                                             '3' => {
                                                      'S' => 5971,
                                                      'H' => 1677,
                                                      'D' => 156,
                                                      'K' => 244,
                                                      'HA' => '28.0857477809412',
                                                      'E' => 68,
                                                      'EA' => '1.13883771562552'
                                                    },
                                                    ...
                                           },
                       'TOP_SKILL_GAME' => {
                                             # top covert xp reached in this game
                                             '6' => '1063655932',
                                             ...
                                           },
                       'TOP_SKILL' => {
                                        # top covert xp reached is 268
                                        '6' => '268',
                                        ...
                                      },
                       'TOP_SCORE_GAME' => '1064606718',
                       'TOP_SCORE' => 1224,
                       'TOP_WEAPONS_GAME' => {
                                               # '19' is mg42, see above
                                               '19' => {
                                                         'S' => '1063653951',
                                                         'H' => '1063653951',
                                                         'D' => '1062883393',
                                                         'K' => '1063653951'
                                                       },
                                                       ...
                                             },
                       'TOP_OBJ_GAME' => '1062885374',
                       'TOP_OBJ' => '4.0970',
                       'TOP_WEAPONS' => {
                                          # '4' is thompson, see above
                                          '4' => {
                                                   'S' => '496',
                                                   'H' => '137',
                                                   'D' => '12',
                                                   'K' => '17',
                                                   'HA' => '27.6209677419355',
                                                   'E' => '8',
                                                   'EA' => '1.61290322580645'
                                                 },
                                                 ...
                                        }
                     },
        ...
        
      };

=cut
