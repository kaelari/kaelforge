#!/usr/bin/perl -w
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);
#use Digest::MD5 qw(md5_hex);
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
$response->{skus}=$kfplatformshared::dbh->selectall_arrayref("SELECT sku, number, accountbound FROM `Inventory` WHERE userId = ?", {Slice =>{}}, $kfplatformshared::player->{userId});



kfplatformshared::end($response);
