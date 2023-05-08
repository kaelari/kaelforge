#!/usr/bin/perl -w
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);
use CGI qw(param);
$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response = {};
kfplatformshared::init();

my $eventid = param("event");
my $eventdata= $kfplatformshared::dbh->selectrow_hashref("SELECT * from `Playerevents` where `playerid` = ? and `eventid` = ? and `finished` =0", undef, ($kfplatformshared::player->{userId}, $eventid));
unless ($eventdata){
    $response->{status}="failed";
    $response->{message}="Not in event";
    end($response);

}

my $baseeventdata = $kfplatformshared::dbh->selectrow_hashref("SELECT * from `events` WHERE `eventid` = ?", undef, ($eventid));
$kfplatformshared::dbh->do("UPDATE `Playerevents` SET `finished` = 1 WHERE `rowid` = ?", undef, ($eventdata->{rowid}));

kfplatformshared::grantprizes($baseeventdata->{$eventdata->{wins}."win"}, $kfplatformshared::player->{UserId});


kfplatformshared::end($response);
