#!/usr/bin/perl -w
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);
use CGI qw(param);
$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response = {};
kfplatformshared::init();
my $achievement=param("achievement");
my $progress = (param("progress") or 1);
my $result=$kfplatformshared::dbh->selectrow_hashref("SELECT * FROM `Achievements` WHERE `achievementid` = ?", undef, ($achievement));
if ($result->{trustclient}){
	
	kfplatformshared::addachievement($platformshared::player->{userId}, $achievement, $progress);
}


kfplatformshared::end($response);
