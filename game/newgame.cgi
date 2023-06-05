#!/usr/bin/perl -w
use lib qw(. /usr/lib/cgi-bin/kfgame);
use CGI qw(param);
use List::Util 'shuffle';
use Data::Dumper;
my $response = {};
$kfgameshared::dbh=kfdb::connectdb();
my $player1=(param("player1") or "");
my $player2=(param("player2") or "");
my $deck1=(param("deck1") or "");
my $deck2=(param("deck2") or "");
my $gameid=(param("gameid") or "");
my $name1=(param("player1name") or "");
my $name2=(param("player2name") or "");
my $avatar1=(param("avatar1") or 0);
my $avatar2=(param("avatar2") or 0);

if ($player1 and $player2 and $deck1 and $deck2 and $gameid){	
	startgame($gameid, $player1, $player2, $deck1, $deck2, $name1, $name2, $avatar1, $avatar2);
}else {
	kfgameshared::debuglog("Error! missing data to make game: $player1 and $player2 and $deck1 and $deck2 and $gameid");
}

sub startgame {
	my $gameid=shift;
	my $player1=shift;
	my $player2=shift;
	my $deck1 =shift;
	my $deck2 = shift;
	my $name1= shift;
	my $name2=shift;
	my $avatar1=shift;
	my $avatar2=shift;
 	$kfgameshared::game = $gameid;
	$kfgameshared::dbh->do("CREATE TABLE `KF_game`.`GameMessages_$gameid` (
   `playerid` int(11) NOT NULL,
  `messageid` int(11) NOT NULL,
  `logmessage` char(255) DEFAULT NULL,
  `changezones` char(255) DEFAULT NULL,
  `changestate` char(255) DEFAULT NULL,
  `changeowner` char(255) DEFAULT NULL,
  `forcedaction` char(255) DEFAULT NULL,
  `turn` int(4) DEFAULT NULL,
  `levels` char(255) DEFAULT NULL,
  `draws` char(10) DEFAULT NULL,
  `handplayable` text CHARACTER SET utf8 COLLATE utf8_unicode_ci DEFAULT NULL,
  `gold` char(255) DEFAULT NULL,
  `life` char(255) DEFAULT NULL,
  `lane` char(255) DEFAULT NULL,
  `object` text CHARACTER SET utf8 COLLATE utf8_unicode_ci DEFAULT NULL,
  `ended` char(2) default NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;");
	$kfgameshared::dbh->do("ALTER TABLE `KF_game`.`GameMessages_$gameid` ADD PRIMARY KEY (`messageid`);");
	$kfgameshared::dbh->do("ALTER TABLE `KF_game`.`GameMessages_$gameid`
  MODIFY `messageid` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=1;");
	srand;
	$kfgameshared::gamedata={};
	$kfgameshared::gamedata->{turn} = 1;
	if (rand(100)<50){
        $kfgameshared::gamedata->{turn}=2;
	}
	$kfgameshared::gamedata->{turnphase}=0;
	$kfgameshared::gamedata->{playsremaining}=1;
	
	$kfgameshared::gamedata->{ended}=0;
	$kfgameshared::gamedata->{lane}= {
				'2' => {
                               '3' => 0,
                               '4' => 0,
                               '5' => 0,
                               '2' => 0,
                               '1' => 0
                             },
                      '1' => {
                               '1' => 0,
                               '5' => 0,
                               '2' => 0,
                               '3' => 0,
                               '4' => 0
                             }
	};
	
	$kfgameshared::gamedata->{players}{1} = {
			threshold => {},
			life => 120,
			moves => 3,
			hand => [],
			playerid => $player1,
			name => $name1,
			id => 1,
			level => 1,
			levelprogress=> 0,
			avatar=> $avatar1,
			};
	
	$kfgameshared::gamedata->{players}{2} = {
			threshold => {},
			life => 120,
			moves => 3,
			hand => [],
			playerid => $player2,
			name => $name2,
			id => 2,
			level => 1,
			levelprogress=> 0,
			avatar=> $avatar2,
			};
	$kfgameshared::gamedata->{objectnumber} = 1;
	my @deck1 = split(/, ?/, $deck1);
	my @deck2 = split(/, ?/, $deck2);
	my @newdeck1;
	my @newdeck2;
	
	foreach my $card (@deck1){
		my $objectnumber = kfgameshared::createobject($card, 1, 0);
		$kfgameshared::gamedata->{objects}{$objectnumber}{zone}="deck";
		push (@newdeck1, $objectnumber);
	}
	foreach my $card (@deck2){
		my $objectnumber = kfgameshared::createobject($card, 2, 0);
		$kfgameshared::gamedata->{objects}{$objectnumber}{zone}="deck";
		push (@newdeck2, $objectnumber);
	}
	@deck1 = shuffle (@newdeck1);
	@deck2 = shuffle (@newdeck2);
	$kfgameshared::gamedata->{deck1}=\@deck1;
	$kfgameshared::gamedata->{deck2}=\@deck2;
	kfgameshared::drawcard(1, 5);
	kfgameshared::drawcard(2, 5);
	kfgameshared::checkplays();
	$kfgameshared::dbh->do("INSERT INTO `KF_game`.`GameData` (`gameid`, `data`) VALUES(?, ?);", undef, ($gameid, Data::Dumper::Dumper($kfgameshared::gamedata)));
	

}
