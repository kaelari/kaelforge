#!/usr/bin/perl -w
use strict;
use warnings FATAL => 'all';
use CGI qw(param);
use HTML::Template;
print "content-type: text/html\n\n";
$kfplatformshared::dbh=kfdbplatform::connectdb();

my %factionconvert = (
	Death => "Nekrium",
	Nature => "Uterra",
	Mechanical => "Alloyin",
	Elemental => "Tempys"
);

if (param("submit")){
	my $name=param("name");
	my $type=param("type");
	my $subtype = param("subtype");
	
	my $old = $kfplatformshared::dbh->selectall_arrayref("SELECT * from `kaelari_solforgeladder`.`cardlevels` WHERE `name`= ? AND `art_type` = 'std' and `cardset` = 'set1' ORDER BY `level` ASC", {Slice=>{}}, ($name));
	$old->[0]{attack} = ($old->[0]{attack} or 0);
	$old->[0]{health} = ($old->[0]{health} or 0);
	$old->[1]{attack} = ($old->[1]{attack} or 0);
	$old->[1]{health} = ($old->[1]{health} or 0);
	$old->[2]{attack} = ($old->[2]{attack} or 0);
	$old->[2]{health} = ($old->[2]{health} or 0);
	$old->[2]{rarity} = ($old->[2]{rarity} or "Token");
	$old->[1]{rarity} = ($old->[1]{rarity} or "Token");
	$old->[0]{rarity} = ($old->[0]{rarity} or "Token");
	
	$kfplatformshared::dbh->do("INSERT INTO `KF_cards`.`carddata`(`Name`, `level`, `CardType`, `subtype`, `Cardart`, `attack`, `health`, `faction`, `rarity`) VALUES(?,?,?,?,?,?,?,?,?)", undef, ($name, 1, $type, $subtype, $old->[0]->{art}, $old->[0]->{attack}, $old->[0]->{health}, $factionconvert{$old->[0]->{faction}}, $old->[0]->{rarity}));
	my $level1id= $kfplatformshared::dbh->{'mysql_insertid'};
	$kfplatformshared::dbh->do("UPDATE `KF_cards`.`carddata` SET `levelsto` = ? + 1 WHERE `CardId` = ? limit 1", undef, ($level1id, $level1id));
	
	$kfplatformshared::dbh->do("INSERT INTO `KF_cards`.`carddata`(`Name`, `level`, `CardType`, `subtype`, `Cardart`, `attack`, `health`, `faction`, `rarity`, `levelsto`, `levels from`) VALUES(?,?,?,?,?,?,?,?,?, ?, ?)", undef, ($name, 2, $type, $subtype, $old->[1]->{art}, $old->[1]->{attack}, $old->[1]->{health}, $factionconvert{$old->[1]->{faction}}, $old->[1]->{rarity}, $level1id+2, $level1id ) );
	
	$kfplatformshared::dbh->do("INSERT INTO `KF_cards`.`carddata`(`Name`, `level`, `CardType`, `subtype`, `Cardart`, `attack`, `health`, `faction`, `rarity`, `levelsto`, `levels from`) VALUES(?,?,?,?,?,?,?,?,?,? ,?)", undef, ($name, 3, $type, $subtype, $old->[2]->{art}, $old->[2]->{attack}, $old->[2]->{health}, $factionconvert{$old->[2]->{faction}}, $old->[2]->{rarity}, $level1id+2, $level1id+1 ) );
	
	
	print "CARDS ADDED !<BR><BR>";
}


my $template = gettemplate(1);
print $template->{html};


sub gettemplate  {
	my $templateid = shift;
	return $kfplatformshared::dbh->selectrow_hashref("SELECT * from `templates` WHERE `templateid` = ?", undef, ($templateid));
}
