#!/usr/bin/perl -w
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);
use Digest::MD5 qw(md5_hex);
use CGI qw(param);
$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response = {};
kfplatformshared::init();

$response->{decks}=$kfplatformshared::dbh->selectall_arrayref("SELECT * from `Decks` WHERE `ownerid` = ? and eventid = 0", {Slice=>{}}, ($kfplatformshared::player->{userId}));




kfplatformshared::end($response);
