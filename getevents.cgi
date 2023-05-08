#!/usr/bin/perl -w
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);
use Digest::MD5 qw(md5_hex);
use CGI qw(param);
$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response = {};
kfplatformshared::init();

$response->{events}=$kfplatformshared::dbh->selectall_arrayref("SELECT * from `events` WHERE `Open` = 1 and `OpenDate` < NOW()", {Slice=>{}}, ());




kfplatformshared::end($response);
