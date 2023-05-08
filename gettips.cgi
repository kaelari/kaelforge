#!/usr/bin/perl -w
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);
use shared;
use CGI qw(param);
$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response = {};
kfplatformshared::init();

$response->{tips}=$kfplatformshared::dbh->selectall_arrayref("SELECT * from `tips` WHERE 1", {Slice=>{}}, ());




kfplatformshared::end($response);
