#!/usr/bin/perl -w
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);
use shared;
use CGI qw(param);
$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response = {};
kfplatformshared::init();
if (!$kfplatformshared::loggedin){
    $response->{status}="failed";
    $response->{message}="Not logged in";
    kfplatformshared::end($response);
}
$response->{result} = $kfplatformshared::dbh->selectall_arrayref("SELECT * from `Playerevents` WHERE `playerid` = ? and `finished` = 0", {Slice=>{}}, ($kfplatformshared::player->{userId}));





kfplatformshared::end($response);
