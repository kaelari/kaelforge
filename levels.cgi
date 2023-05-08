#!/usr/bin/perl -w
use strict "vars";
use lib qw(.);
use Digest::MD5 qw(md5_hex);
use CGI qw(param);
my $response = {};
kfplatformshared::init();
$response->{levels} = $kfplatformshared::levels;
$response->{exp} =$kfplatformshared::player->{"currentexp"};
$response->{level} = $kfplatformshared::player->{"level"};

kfplatformshared::end($response);
