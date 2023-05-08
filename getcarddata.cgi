#!/usr/bin/perl -w
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);
use shared;
use CGI qw(param);
$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response = {};
kfplatformshared::init();
$response->{result}=$kfplatformshared::dbh->selectall_arrayref("SELECT * FROM `KF_cards`.`carddata` ORDER BY `cardid`", {Slice =>{}}, ());




kfplatformshared::end($response);
