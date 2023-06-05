package kfgameshared;
use strict;
use warnings FATAL => 'all';
use CGI::Carp qw(fatalsToBrowser);
use CGI qw(param);
use POSIX qw(ceil floor);
use Data::Dumper;
use CGI::Cookie;
use DateTime;
use JSON;
use IO::Handle;
use List::Util 'shuffle';

our $platformdb = 'KF_Platform';
our $player;
our $dbh;
our $gamedata;
our $allcards;
our $game;
our $loggedin=0;
our $alltriggers;
our $alltargets;
our $allactivated;
our $logfilehandle;
our @triggered;

require ("/usr/lib/perl/game/kfdb.pm");
$kfgameshared::dbh=kfdb::connectdb();

$allcards=loadcards();
$alltriggers=loadtriggers();
$alltargets=loadtargets();
$allactivated = loadactivated();
our $alleffects = loadeffects();
our $allstatic = loadstatic();

open($logfilehandle, ">>", "/var/log/ladder/kfgame.log") or die ($_);
$logfilehandle->autoflush;
debuglog("started");


sub debuglog {
    #my ($package, $filename, $line) = caller;
    #print $logfilehandle "$package, $filename, $line\n";
    print $logfilehandle caller;
    print $logfilehandle "\n";
    print $logfilehandle @_;
	print $logfilehandle "\n";
}

sub init {
	$loggedin=0;
	initquiet();
}
sub initquiet {
	my %cookies = CGI::Cookie->fetch;
	$kfgameshared::dbh=kfdb::connectdb();

	$dbh->do("USE `KF_game`");

	my $sid = param("session");

	my $sql = "SELECT * from $platformdb.sessionId WHERE session like ?;";
	my $sessiondata=$dbh->selectrow_hashref($sql, undef, ($sid));
	$sql="SELECT * from $platformdb.`Users` where `userId` = ?;";
	$player = $dbh->selectrow_hashref($sql, undef, $sessiondata->{userId});



	if ($player->{userId}){
            $loggedin=1;
	}else {
		$loggedin = 0;
	}

}

sub loadgame {
    my $gamenumber=shift;
	$game=$gamenumber;
    my $dbdata=$dbh->selectrow_hashref("SELECT * from `GameData` WHERE `gameid` = ?", undef, ($gamenumber));
    if (!$dbdata->{data}){ 
    }else {
    	local $@;
		$gamedata=eval("my $dbdata->{data}");
		if (!$gamedata){
			warn $@;
			die;
		}
	}
}

sub checkstatebased {
	#check if Creatures died
	my $game=(shift or $kfgameshared::game);
	my $lanestring;
	my @triggers;
	my @triggerold = @triggered;
	my $changed = 0;
	@triggered = ();
	while (@triggerold > 0){
        debuglog("Something triggered!".scalar @triggerold);
        my $trigger = shift(@triggerold);
        debuglog("applying our triggers: ".Data::Dumper::Dumper($trigger));
        applytrigger($trigger);
        
        $changed = 1;
	}
	if ($gamedata->{forceplay}){
		my $string = to_json($gamedata->{forceplay}[0]);
		
		my $weare = $gamedata->{turn};
		
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `forcedaction`) VALUES(?, ? )", undef, ($gamedata->{players}{$weare}{playerid},  $string));
		if ($gamedata->{forceplay}[0]{revealtargets} ){
			foreach my $target (@{$gamedata->{forceplay}[0]{targets}[0]{raw}}){
				
				my $objectstring = "$target:".to_json($gamedata->{objects}{ $target});
				$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, ($gamedata->{players}{$weare}{playerid},  $objectstring ));
			
			}
		}
	}
	for my $lane (1..5){
        if ($gamedata->{lane}{1}{$lane} > 0 ){
			if ($gamedata->{objects}{$gamedata->{lane}{1}{$lane}}{newtriggers}){
				my $object = $gamedata->{objects}{ $gamedata->{lane}{1}{$lane} };
				if (!$object->{triggers}){
					$object->{triggers}=[];
				}
				push (@{$object->{triggers}}, @{$object->{newtriggers}});
				delete $object->{newtriggers};
			}
		}
        if ($gamedata->{lane}{2}{$lane} > 0 ){
			if ($gamedata->{objects}{$gamedata->{lane}{2}{$lane}}{newtriggers}){
				my $object = $gamedata->{objects}{ $gamedata->{lane}{2}{$lane} };
				if (!$object->{triggers}){
					$object->{triggers}=[];
				}
				push (@{$object->{triggers}}, @{$object->{newtriggers}});
				delete $object->{newtriggers};
			}
		}
		if ($gamedata->{lane}{1}{$lane}>0 and $gamedata->{objects}{ $gamedata->{lane}{1}{$lane} }{"Health"} <= 0){
			my $died=$gamedata->{objects}{ $gamedata->{lane}{1}{$lane} };
			
			$died->{"zone"} = "graveyard";
			$gamedata->{lane}{1}{$lane} = 0;
			$lanestring.="1:$lane:0;";
			push (@triggers, ["died", $died]);
			
		}
		if ($gamedata->{lane}{2}{$lane}>0 and $gamedata->{objects}{ $gamedata->{lane}{2}{$lane} }{"Health"} <= 0){
			my $died= $gamedata->{objects}{ $gamedata->{lane}{2}{$lane} };
			
			$died->{"zone"} = "graveyard";
			$gamedata->{lane}{2}{$lane} = 0;
			$lanestring.="2:$lane:0;";
			push (@triggers, ["died", $died]);
			
		}
	}
	if ($lanestring) {
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `lane`) VALUES(?, ?)", undef, (0, $lanestring) );
   
	}
	foreach my $triggers (@triggers){
		checktriggers($triggers->[0], $triggers->[1]);
	}
	my $z=0;
	
	while ($z < $gamedata->{objectnumber}){
		unless ($gamedata->{objects}{$z} and $gamedata->{objects}{$z}{zone}) {
				$z++;
				next;
		};
		foreach my $static (@{$gamedata->{objects}{$z}{static}}) {
			if ($allstatic->{$static}{"zone"} ne $gamedata->{objects}{$z}{zone}){
                next;
			}
			#check if this ability should be active
# 			debuglog("Checking this static ability of $z. $static");
			if ($allstatic->{$static}{"target"} eq "self"){
				if (checktarget($allstatic->{$static}{conditional}, $z, $z, $gamedata->{objects}{$z}{owner} )) {
					#debuglog("We should be under this effect");
					#we should be under effect, lets check if we already are
					if ($gamedata->{objects}{$z}{undereffect}{"$z - $static"}){
						next;
					}else {
						$gamedata->{objects}{$z}{undereffect}{"$z - $static"}= 1;
						my $effect = $allstatic->{$static}{effect};
						
						applyeffects( { effecttype=> $alleffects->{$effect}{effecttype}, 
													effecttarget => $alleffects->{$effect}{effecttarget},
													effectmod1 => $alleffects->{$effect}{effectmod1},
													expires => $alleffects->{$effect}{expires},
													target => [$z],
													effectcontroller => $gamedata->{objects}{$z}{owner},
													} );
					}
				}else {
					#debuglog("We should not be under this effect");
					if ($gamedata->{objects}{$z}{undereffect}{"$z - $static"}){
						debuglog("Removing effect");
						delete $gamedata->{objects}{$z}{undereffect}{"$z - $static"};
						my $effect = $allstatic->{$static}{effect};
						removeeffect2($z, {'target' => [
												$z,
											],
													
								'effectcontroller' => $gamedata->{objects}{$z}{owner},
								'effecttype' => $alleffects->{$effect}{effecttype},
								'effecttarget' => $alleffects->{$effect}{effecttarget},
								'effectmod1' => $alleffects->{$effect}{effectmod1} } );
						#removeeffect2($alleffects->{$effect}{effecttype}, $alleffects->{$effect}{effecttarget}, $alleffects->{$effect}{effectmod1},  [$z], $gamedata->{objects}{$z}{owner});
						next;
					}else {
					}
				}
			}else {
				if (checktarget($allstatic->{$static}{conditional}, $z, $z,  $gamedata->{objects}{$z}{owner} ) and ($gamedata->{objects}{$z}{zone} eq $allstatic->{$static}{zone}) ) {
# 					debuglog("$z has a static ability, checking targets");
					my ($lane, $olane, $raw, $totalvalidtargets, $variables, $players) = findtargets_revised($gamedata->{objects}{$z}{owner}, $allstatic->{$static}{targetindex}, $z);
					debuglog(Data::Dumper::Dumper($lane, $olane, $raw));
					foreach my $lane (@{$lane}){
						my $object = $gamedata->{lane}{$gamedata->{objects}{$z}{owner} }{$lane};
						if ($gamedata->{objects}{$object}{undereffect}{"$z - $static"}){
							next;
						}else {
							$gamedata->{objects}{$object}{undereffect}{"$z - $static"}= 1;
							my $effect = $allstatic->{$static}{effect};
						
							applyeffects( { effecttype=> $alleffects->{$effect}{effecttype}, 
													effecttarget => $alleffects->{$effect}{effecttarget},
													effectmod1 => $alleffects->{$effect}{effectmod1},
													expires => $alleffects->{$effect}{expires},
													target => [$object],
													effectcontroller => $gamedata->{objects}{$z}{owner},
													} );
						}
					}
					foreach my $lane (@{$olane}){
						my $opp = 1;
						if ($gamedata->{objects}{$z}{owner} == 1){
							$opp = 1;
						}
						my $object = $gamedata->{lane}{$opp }{$lane};
						if ($gamedata->{objects}{$object}{undereffect}{"$z - $static"}){
							next;
						}else {
							$gamedata->{objects}{$object}{undereffect}{"$z - $static"}= 1;
							my $effect = $allstatic->{$static}{effect};
						
							applyeffects( { effecttype=> $alleffects->{$effect}{effecttype}, 
													effecttarget => $alleffects->{$effect}{effecttarget},
													effectmod1 => $alleffects->{$effect}{effectmod1},
													expires => $alleffects->{$effect}{expires},
													target => [$object],
													effectcontroller => $gamedata->{objects}{$z}{owner},
													} );
						}
					}
					foreach my $lane (@{$raw}){
						
						my $object = $lane;
						if ($gamedata->{objects}{$object}{undereffect}{"$z - $static"}){
							next;
						}else {
							$gamedata->{objects}{$object}{undereffect}{"$z - $static"}= 1;
							my $effect = $allstatic->{$static}{effect};
						
							applyeffects( { effecttype=> $alleffects->{$effect}{effecttype}, 
													effecttarget => $alleffects->{$effect}{effecttarget},
													effectmod1 => $alleffects->{$effect}{effectmod1},
													expires => $alleffects->{$effect}{expires},
													target => [$object],
													effectcontroller => $gamedata->{objects}{$z}{owner},
													} );
						}
					}
					
					
				
				}
			
			}
		}
# 		debuglog("Made it here");
		outer: foreach my $undereffect ( keys %{ $gamedata->{objects}{$z}{undereffect} } )  {
			$undereffect =~/(\d+) - (\d+)/;
			if ($1 eq $z) {
				next;
			}
			my $source = $gamedata->{objects}{$1};
			my $effect = $2;
			if ($gamedata->{objects}{$1}{zone} eq $allstatic->{$effect}{zone}){
# 				debuglog("Verifying static ability for object $z, from $1, effect $2");
				
				my ($lane, $olane, $raw, $totalvalidtargets, $variables, $players) = findtargets_revised ($source->{owner}, $allstatic->{$effect}{targetindex}, $1);
				if ($gamedata->{objects}{$z}{zone} eq "play") {
					debuglog("still in play so we should check if we're valid target");
					if ($source->{owner} == $gamedata->{objects}{$z}{owner}){
						foreach my $lane (@{$lane}){
							if ($gamedata->{objects}{$z}{lane} == $lane){
								next outer;
							}
						}
					}else {
						foreach my $lane (@{$olane}){
							if ($gamedata->{objects}{$z}{lane} == $lane){
								next outer;
							}
						}
					}
				}else {
					foreach my $lane (@{$raw}){
						if ($z == $raw){
							next outer;
						}
					}
				}
			}
			#if we made it here this is no longer a valid static ability
			debuglog("Removing static ability $effect from $z");
			my $effect2 = $allstatic->{$effect}{effect};
			removeeffect2($z, {'target' => [
												$z,
											],
													
								'effectcontroller' => $gamedata->{objects}{$z}{owner},
								'effecttype' => $alleffects->{$effect2}{effecttype},
								'effecttarget' => $alleffects->{$effect2}{effecttarget},
								'effectmod1' => $alleffects->{$effect2}{effectmod1} } );
			#removeeffect2($alleffects->{$effect2}{effecttype}, $alleffects->{$effect2}{effecttarget}, $alleffects->{$effect2}{effectmod1},  [$z], $gamedata->{objects}{$z}{owner});
			delete $gamedata->{objects}{$z}{undereffect}{$undereffect};
		}
		
		$z++;
	}
	
	
	checkendgame();
	if ((scalar @triggers > 0) or ($changed > 0 ) or (@triggered > 0)){ 
		checkstatebased($game);
	}
}


sub checktriggers { 
	#the type of trigger that occured
	my $type=shift;
	#The object if any that caused the trigger to happen. such as the Creature that entered play. undef for triggers caused by non-cards such
	#as moving on the wheel.
	my $triggerobject=shift;
	my $variables = shift;
	my $secondobject=shift;
	
	our $weare = 0;
	our $opp = 0;
	
	#this won't work if things trigger on opponent's turn... 
	if ($gamedata->{turn} == 1 ){
		$weare=1;
		$opp=2;
	}else {
		$weare=2;
		$opp=1;
	}
	my $z=0;
	debuglog("Checking triggers for $type");
	if (!ref $triggerobject && defined($triggerobject) && $triggerobject > 0){
        $triggerobject=$gamedata->{objects}{$triggerobject};
	}
	if ($triggerobject){
        debuglog($triggerobject->{id});
	}
	while ($z <= $gamedata->{objectnumber}){
		unless ($gamedata->{objects}{$z} and $gamedata->{objects}{$z}{zone}) {
				$z++;
				next;
		};
		
		if (@{$gamedata->{objects}{$z}{triggers}} > 0){
			foreach my $trigger (@{$gamedata->{objects}{$z}{triggers}}){
					#does this trigger trigger?
					
					if ($alltriggers->{$trigger}{type} ne $type or $alltriggers->{$trigger}{zone} ne $gamedata->{objects}{$z}{zone}){
						next;
					}
					checktriggersinner ( $gamedata->{objects}{$z}, $trigger, $triggerobject, $type, $weare, $variables, $secondobject);
				}
		}
		$z++;
	}
	
		
		
	if ($gamedata->{forceplay}){
		my $string = to_json($gamedata->{forceplay}[0]);
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `forcedaction`) VALUES(?, ? )", undef, ($gamedata->{players}{$weare}{playerid},  $string));
		if ($gamedata->{forceplay}[0]{revealtargets} ){
			foreach my $target (@{$gamedata->{forceplay}[0]{targets}[0]{raw}}){
				
				my $objectstring = "$target:".to_json($gamedata->{objects}{ $target});
				$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, ($gamedata->{players}{$weare}{playerid},  $objectstring ));
			
			}
		}
	}
	foreach my $lane (1..5) {
		if ($gamedata->{lane}{$weare}{$lane} > 0 ){
			if ($gamedata->{objects}{$gamedata->{lane}{$weare}{$lane}}{newtriggers}){
				my $object = $gamedata->{objects}{ $gamedata->{lane}{$weare}{$lane} };
				if (!$object->{triggers}){
					$object->{triggers}=[];
				}
				push (@{$object->{triggers}}, @{$object->{newtriggers}});
				delete $object->{newtriggers};
				
				
				
				
			}
		}
	}
	
	
}

sub checktriggersinner {
	my $self = shift;
	my $object = $self->{id};
	my $trigger = shift;
	my $triggerobject = shift;
	my $type = shift;
	my $weare = shift;
	my $variables= (shift or {});
	my $secondobject = shift;
	
	my $opp = 2;
	if ($weare == 2){
		$opp = 1;
	}
	my $target = {};
	if ($triggerobject){
		$target=$triggerobject;
	}
				
	#we could increase this if we ever need more fields
	for my $i (1..4) {
		my $trigger2 = $alltriggers->{$trigger}{"trigger$i"};
		my $compare2 = $alltriggers->{$trigger}{"compare$i"};
		my $target2 = $alltriggers->{$trigger}{"target$i"};
        debuglog("$self, $target, $trigger2, $compare2, $target2, $variables");
        if (!triggercompare($self, $target, $trigger2, $compare2, $target2, $variables, $secondobject)) {
			return;
		}
    }
					
    #trigger does in fact trigger
                
    if ($triggerobject){ 
        $variables->{triggerobject}=$triggerobject;
    }
    if ($secondobject){
        $variables->{secondobject}=$secondobject;
    }
    $variables->{self}=$self;
                
    debuglog( "inner check: $self, ".Dumper($object).", ".Dumper($alltriggers->{$trigger}).", $type, $weare");
					
    push (@triggered, {trigger=> $trigger, variables => $variables, type=> $type, secondobject => $secondobject, object => $object, triggerobject => $triggerobject, target => $target, weare=> $weare, opp => $opp});
}

sub applytrigger {
    my $data = shift;
    my $trigger = $data->{trigger};
    my $secondobject = $data->{secondobject};
    my $object = $data->{object};
    my $self = $gamedata->{objects}{$object};
    my $triggerobject = $data->{triggerobject};
    my $variables= $data->{variables};
    my $target = $data->{target};
    my $weare = $data->{weare};
    my $opp = $data->{opp};
    
    
    
    my @targets;
    if ($alltriggers->{$trigger}{targettype} eq "secondobject"){
        push @targets, $secondobject;
        my @effects = split (/,/, $alltriggers->{$trigger}{effectindexes});
        foreach my $effect (@effects) {
            applyeffects( {
										effecttype => $alleffects->{$effect}{effecttype}, 
										effecttarget => $alleffects->{$effect}{effecttarget},
										effectmod1 => $alleffects->{$effect}{effectmod1}, 
										expires => $alleffects->{$effect}{expires},
										target => [$secondobject], 
										effectcontroller => $self->{owner},
										variables=> $variables,
										} );
            debuglog("applying effect! $effect -  $alleffects->{$effect}{effecttype}, $alleffects->{$effect}{effecttarget},$alleffects->{$effect}{effectmod1}, [$target], $weare ");
        }
								
    }elsif ($alltriggers->{$trigger}{targettype} eq "allcards"){
                        debuglog("this is an allcards trigger, checking all cards for validity");
                        my ($targets, $totalvalidtargets) = findtargetsallzones($weare, $alltriggers->{$trigger}{targetindex}, $object);
                        
                        if ($totalvalidtargets < $alltargets->{ $alltriggers->{$trigger}{targetindex} }{mintargets} ){
                            debuglog("no targets for this trigger");
                            
                            return;
                        }
                        
                        if ($alltargets->{ $alltriggers->{$trigger}{targetindex} }{Selector} eq "Player"){
                        
                            if ( !$gamedata->{forceplay} ) {
                                $gamedata->{forceplay}=[];
                            }
                            push (@{$gamedata->{forceplay}}, {trigger => $trigger, revealtargets => 1,
                        source => $object, targets=>[{'text' => $alltargets->{$target}{text},
                                l => [],
                                o => [],
                                raw => $targets }] } );
                        }
                        if ($alltargets->{ $alltriggers->{$trigger}{targetindex} }{Selector} eq "Random"){
                            my @effects = split (/,/, $alltriggers->{$trigger}{effectindexes});
                            @targets = shuffle(@{$targets});
                            debuglog("targets: @targets");
                            foreach my $effect (@effects) {
                                applyeffects( {
                                    effecttype => $alleffects->{$effect}{effecttype}, 
                                    effecttarget => $alleffects->{$effect}{effecttarget},
                                    effectmod1 => $alleffects->{$effect}{effectmod1}, 
                                    expires => $alleffects->{$effect}{expires},
                                    target => \@targets, 
                                    effectcontroller => $self->{owner},
                                    variables => $variables,
                                    } );
                            }
                        }
                    }elsif ($alltriggers->{$trigger}{targettype} eq "self"){						
                        push @targets, $object;
                        my @effects = split (/,/, $alltriggers->{$trigger}{effectindexes});
                        
                                foreach my $effect (@effects) {
                                    applyeffects( {
                                        effecttype => $alleffects->{$effect}{effecttype}, 
                                        effecttarget => $alleffects->{$effect}{effecttarget},
                                        effectmod1 => $alleffects->{$effect}{effectmod1}, 
                                        expires => $alleffects->{$effect}{expires},
                                        target => [$object], 
                                        effectcontroller => $self->{owner},
                                        variables => $variables,
                                        } );
                                    debuglog("applying effect! $effect -  $alleffects->{$effect}{effecttype}, $alleffects->{$effect}{effecttarget},$alleffects->{$effect}{effectmod1}, [$target], $weare ");
                                }
                                
                    }	elsif  ($alltriggers->{$trigger}{targettype} eq "multi") {
                        debuglog("multi trigger");
                        my @targetindexes = split(/,/, $alltriggers->{$trigger}{targetindexes});
                        my @targetinfo;
                        foreach my $index (@targetindexes){
                            debuglog("index is $index");
                            my ($lane, $olane, $totalvalidtargets, $variables)  = findtargets($weare, $index, $self->{id}); 
                                                    
                            if ($totalvalidtargets < $alltargets->{$index}{mintargets} ){
                                return;
                            }
                            my $targetinfo ={};
                            $targetinfo->{text} = $alltargets->{$index}{text};
                            $targetinfo->{l} = $lane;
                            $targetinfo->{o} = $olane;
                            push (@targetinfo, $targetinfo);
                        }
                        
                        if ( !$gamedata->{forceplay} ) {
                            $gamedata->{forceplay}=[];
                        }
                        push (@{$gamedata->{forceplay}}, {trigger => $trigger, source => $object, targets=> \@targetinfo } );
                            
                    }elsif  ($alltriggers->{$trigger}{targettype} eq "single") {
                        debuglog("player choice trigger");
                        my ($lane, $olane, $raw, $totalvalidtargets, $variables, $players)  = findtargets_revised($weare, $alltriggers->{$trigger}{targetindex}, $self->{id}); 
                        if ($alltargets->{ $alltriggers->{$trigger}{targetindex} }{targettype} eq "lane"){
                            foreach my $target ( @{$lane}){
                                push (@targets, "l$target");
                            }
                            foreach my $target ( @{$olane}){
                                push (@targets, "o$target");
                            }
                        }else {
                            foreach my $target ( @{$lane}){
                                if ($target =~/^\d+$/){
                                    push @targets, $gamedata->{lane}{$weare}{$target};
                                }else {
                                    push (@targets, $target);
                                }
                            }   
                            foreach my $target ( @{$olane}){
                                if ($target =~/^\d+$/){
                                    push @targets, $gamedata->{lane}{$opp}{$target};
                                }else {
                                    push (@targets, $target);
                                }
                            }
                            if ($totalvalidtargets == 0 ){
                                return;
                            }
                        }
                        if ($alltargets->{ $alltriggers->{$trigger}{targetindex} }{Selector} eq "Random"){
                            debuglog("Random target!". Data::Dumper::Dumper(\@targets));
                            @targets = shuffle(@targets);
                            $variables->{source} = $object;
                            my @effects = split (/,/, $alltriggers->{$trigger}{effectindexes});
                        
                                foreach my $effect (@effects) {
                                    applyeffects( {
                                        effecttype => $alleffects->{$effect}{effecttype}, 
                                        effecttarget => $alleffects->{$effect}{effecttarget},
                                        effectmod1 => $alleffects->{$effect}{effectmod1}, 
                                        expires => $alleffects->{$effect}{expires},
                                        target => \@targets, 
                                        effectcontroller => $self->{owner},
                                        variables => $variables,
                                        } );
                                    debuglog("applying effect! $effect -  $alleffects->{$effect}{effecttype}, $alleffects->{$effect}{effecttarget},$alleffects->{$effect}{effectmod1}, [$target], $weare ");
                                }
                        }else {
                        
                            
                            if ( !$gamedata->{forceplay} ) {
                                $gamedata->{forceplay}=[];
                            } 
                            push (@{$gamedata->{forceplay}}, {trigger => $trigger, source => $object, targets=>[{'text' => $alltargets->{$alltriggers->{$trigger}{targetindex}}{text},
                                l => $lane,
                                o => $olane,
                                players=> $players}] } );
                        }
                        
                    }elsif ($alltriggers->{$trigger}{targettype} eq "cardinhand"){
                        my @raw;
                        my $totalvalidtargets= 0;
                        foreach my $card (@{$gamedata->{players}{$weare}{hand}} ){
                            if (checktarget($alltriggers->{$trigger}{targetindex}, $card, $object, $weare)){
                                push (@raw, $card);
                                $totalvalidtargets ++;
                            }
                        }
                        
                        if ($totalvalidtargets == 0 ) {
                            return;
                        }
                        if ( !$gamedata->{forceplay} ) {
                            $gamedata->{forceplay}=[];
                        }
                        push (@{$gamedata->{forceplay}}, {trigger => $trigger, 	source => $object, targets=>[{'text' => $alltargets->{$target}{text},
                            l => [],
                            o => [],
                        
                            
                            raw => \@raw }] } );
                        
                        
                    } elsif ($alltriggers->{$trigger}{targettype} eq "all"){
                        #need to check all possible targets;
                        debuglog("all type trigger");
                        my ($lane, $olane, $totalvalidtargets, $tmp)  = findtargets($weare, $alltriggers->{$trigger}{targetindex}, $self->{id}); 
                        foreach my $key (keys %{$tmp}){
                            $variables->{$key}=$tmp->{$key};
                        }
                        foreach my $target ( @{$lane}){
                            push @targets, $gamedata->{lane}{$weare}{$target};
                        }
                        foreach my $target ( @{$olane}){
                            push @targets, $gamedata->{lane}{$opp}{$target};
                        }
                        
                        if ($totalvalidtargets < $alltargets->{$alltriggers->{$trigger}{targetindex}}{mintargets} ){
                            return;
                        }
                        foreach my $target (@targets) {
                            
                            if ($alltriggers->{$trigger}{effecttype} eq "neweffect")
                            {
                                debuglog("new effect type");
                                my @effects = split (/,/, $alltriggers->{$trigger}{effectindexes});
                                foreach my $effect (@effects) {
                                    applyeffects( {
                                        effecttype => $alleffects->{$effect}{effecttype}, 
                                        effecttarget => $alleffects->{$effect}{effecttarget},
                                        effectmod1 => $alleffects->{$effect}{effectmod1}, 
                                        expires => $alleffects->{$effect}{expires},
                                        target => [$target, $object], 
                                        effectcontroller => $self->{owner},
                                        variables=> $variables,
                                        } );
                                    debuglog("applying effect! $effect -  $alleffects->{$effect}{effecttype}, $alleffects->{$effect}{effecttarget},$alleffects->{$effect}{effectmod1}, [$target], $weare ");
                                }
                                
                                
                                
                            }else {
                                
                                applyeffects( {
                                    effecttype => $alltriggers->{$trigger}{effecttype}, 
                                    effecttarget => $alltriggers->{$trigger}{effecttarget},
                                    effectmod1 => $alltriggers->{$trigger}{effectmod1},
                                    expires => $alltriggers->{$trigger}{expires},
                                    target => [$target],
                                    effectcontroller => $self->{owner},
                                    variables=> $variables,
                                    });
                            }
                        }
                        
                    }elsif ($triggerobject) {
                        debuglog("We're trying to apply effect to a trigger object");
                        
                        push @targets, $object;
                        push @targets, $triggerobject->{id};
                        my @effects = split (/,/, $alltriggers->{$trigger}{effectindexes});
                        foreach my $effect (@effects) {
                            applyeffects( {
                                        effecttype => $alleffects->{$effect}{effecttype}, 
                                        effecttarget => $alleffects->{$effect}{effecttarget},
                                        effectmod1 => $alleffects->{$effect}{effectmod1}, 
                                        expires => $alleffects->{$effect}{expires},
                                        target => \@targets, 
                                        effectcontroller => $self->{owner},
                                        variables=> $variables,
                                        } );
                        }
                    }else {
                        push @targets, $object;
                        applyeffects({
                            effecttype => $alltriggers->{$trigger}{effecttype},
                            effecttarget => $alltriggers->{$trigger}{effecttarget},
                            effectmod1 => $alltriggers->{$trigger}{effectmod1}, 
                            expires => $alltriggers->{$trigger}{expires},
                            target => \@targets,
                            effectcontroller =>  $self->{owner},
                            });
                        
                    }
                    
                    
                    
                        my $message = $alltriggers->{$trigger}{log};
                        $message=~ s/\%player\%/$gamedata->{players}{$weare}{name}/;
                        
                        $message=~ s/\%name\%/<link=$self->{CardId}><color=#000000>$self->{Name}<\/color><\/link>/;
                        logmessage($message);
                        
                        my $controller = $gamedata->{objects}{$object}{owner};
                        
                        if ($alltriggers->{$trigger}{oneshot})
                        {
                            for( my $i=0; $i<=@{$gamedata->{objects}{$object}{triggers}}; $i++){
                                    if ($gamedata->{objects}{$object}{triggers}[$i] == $trigger){
                                        splice @{ $gamedata->{objects}{$object}{triggers} }, $i, 1;
                                        debuglog("removing this one shot trigger");
                                        #last;
                                    }
                            }
                            
                        }
                        
}

sub applyeffects {
	my $data = shift;
	my $effecttype = $data->{effecttype};
	my $effecttarget = $data->{effecttarget};
	my $effectmod1= $data->{effectmod1};
	my $targets = $data->{target};
	my $targetcontroller= ($data->{targetcontroller} or 0);
	my $effectcontroller = $data->{effectcontroller};
	my $targetindex = ($data->{targetindex} or 0);
	my $variables = ($data->{variables} or {});
	
	
	if (! defined $effectmod1){
        $effectmod1 = "";
	}
	
	foreach my $target (@{$targets}){
		if (ref($target) eq 'HASH'){
			foreach my $a (keys %{$target->{variables}}){
				$variables->{$a}=$target->{variables}{$a};
			}
			$target = $target->{target};
		}
	}
	
	
	if ($effecttarget =~/target(\d+)/i){
		$targetindex= $1;
	}
	
	
	
	
	
	if (defined $targets->[$targetindex]) {
        if (defined $gamedata->{objects}{$targets->[$targetindex]}){
            $targetcontroller = $gamedata->{objects}{$targets->[$targetindex]}{owner};
		}
	}
	if ($effectmod1 =~/variable.(.*)$/i){
        my @results = split(/\./, $effectmod1);
        if (@results == 2){
            $effectmod1 = $variables->{$results[1]};
        }
        if ($results[1] eq "target0"){
            my $object;
            debuglog(Data::Dumper::Dumper($targets));
            if ($targets->[0] =~/^l(\d+)/){
                $object = $gamedata->{lane}{$effectcontroller}{$1};
            }elsif ($targets->[0] =~/^ol(\d+)/){
                my $opp = 2;
                if ($effectcontroller == 2){
                    $opp = 1;
                }
                $object = $gamedata->{lane}{$opp}{$1};
            }else {
                $object = $targets->[0];
            }
            
            
            $effectmod1 = $gamedata->{objects}{$object}{$results[2]};
        }elsif (@results == 3){
            $effectmod1 = $variables->{$results[1]}{$results[2]};
        }
	}
	if (defined $effectmod1){
        if ($effectmod1 =~ /builtin.(.*)$/i){
            if ($1 eq "alloyininhand"){
                my $count = 0;
                foreach my $card (@{$gamedata->{players}{$effectcontroller }{hand}}){
                    if ($gamedata->{objects}{$card}{Faction} eq "Alloyin"){
                        $count +=1;
                    }
                }
                $effectmod1 = $count;
            }
            if ($1 eq "uterrainhand"){
                my $count = 0;
                foreach my $card (@{$gamedata->{players}{$effectcontroller }{hand}}){
                    if ($gamedata->{objects}{$card}{Faction} eq "Uterra"){
                        $count +=1;
                    }
                }
                $effectmod1 = $count;
            }
            if ($1 eq "nekriuminhand"){
                my $count = 0;
                foreach my $card (@{$gamedata->{players}{$effectcontroller }{hand}}){
                    if ($gamedata->{objects}{$card}{Faction} eq "Nekrium"){
                        $count +=1;
                    }
                }
                $effectmod1 = $count;
            }
            if ($1 eq "tempysinhand"){
                my $count = 0;
                foreach my $card (@{$gamedata->{players}{$effectcontroller }{hand}}){
                    if ($gamedata->{objects}{$card}{Faction} eq "Tempys"){
                        $count +=1;
                    }
                }
                $effectmod1 = $count;
            }
            
        }
	}
	if (!$effecttype){
 		debuglog("empty effecttype!".caller);
		exit;
	}
	debuglog("applying: $effecttype to $effecttarget with mod of $effectmod1 . $effectcontroller.");
	debuglog(Data::Dumper::Dumper($targets));
	if ($data->{expires}){
		debuglog("this effect will expire in $data->{expires} turns");
		if (!defined $gamedata->{objects}{$targets->[$targetindex]}{expires} ){
			$gamedata->{objects}{$targets->[$targetindex]}{expires} = [];
		}
		my %info = ();
		$info{effecttype}=$effecttype;
		$info{effecttarget}=$effecttarget;
		$info{effectmod1}=$effectmod1;
		$info{targetindex}=($data->{targetindex} or 0);
		
		push(@{$gamedata->{objects}{$targets->[$targetindex]}{expires}}, { turns=> $data->{expires}, data=> \%info});
	}
	my $opp=1;
	if ($effectcontroller == 1 ){
		$opp=2;
	}
	if ($effecttype eq "drawspecific"){ 
		#push(@{$gamedata->{players}{$weare }{hand}}, pop @{$gamedata->{"deck$weare"}});
		if ($gamedata->{objects}{$targets->[$targetindex]}{owner} eq $effectcontroller){
			if ($gamedata->{objects}{$targets->[$targetindex]}{zone} eq "deck"){
				for	(my $i=0; $i<@{$gamedata->{"deck$effectcontroller"}}; $i++){
					if ($gamedata->{"deck$effectcontroller"}[$i] == $targets->[$targetindex] ){
						push (@{$gamedata->{players}{$effectcontroller }{hand}},    splice(@{$gamedata->{"deck$$effectcontroller"}}, $i, 1));
						last;
					}
				}
			}elsif ($gamedata->{objects}{$targets->[$targetindex]}{zone} eq "discard" ) {
				for	(my $i=0; $i<@{$gamedata->{players}{$effectcontroller}{discard}}; $i++){
                    
					if ($gamedata->{players}{$effectcontroller}{discard}[$i] == $targets->[$targetindex] ){
                        debuglog("we are drawing this card from our discard.");
                        my $card = splice(@{$gamedata->{players}{$effectcontroller}{discard}}, $i, 1);
                        debuglog("card=$card");
                        push (@{$gamedata->{players}{$effectcontroller }{hand}},   $card );
						last;
					}
				}
			}
		}else {
			debuglog("We're not the owner of the target. $targets->[$targetindex]");
			if ($gamedata->{objects}{$targets->[$targetindex]}{zone} eq "deck"){
				for	(my $i=0; $i<@{$gamedata->{"deck$targetcontroller"}}; $i++){
					if ($gamedata->{"deck$targetcontroller"}[$i] == $targets->[$targetindex] ){
						push (@{$gamedata->{players}{$effectcontroller }{hand}},    splice(@{$gamedata->{"deck$targetcontroller"}}, $i, 1));
						last;
					}
				}
			}elsif ($gamedata->{objects}{$targets->[$targetindex]}{zone} eq "discard" ) {
				for	(my $i=0; $i<@{$gamedata->{players}{$targetcontroller}{discard}}; $i++){
					if ($gamedata->{players}{$targetcontroller}{discard}[$i] == $targets->[$targetindex] ){
						push (@{$gamedata->{players}{$effectcontroller }{hand}},    splice(@{$gamedata->{players}{$targetcontroller}{discard}}, $i, 1));
						last;
					}
				}
			}elsif ($gamedata->{objects}{$targets->[$targetindex]}{zone} eq "hand" ) {
				debuglog("it's in our opponent's hand");
				for	(my $i=0; $i<@{$gamedata->{players}{$targetcontroller}{hand}}; $i++){
					debuglog("$i: $gamedata->{players}{$targetcontroller}{hand}[$i]  - $targets->[$targetindex]");
					if ($gamedata->{players}{$targetcontroller}{hand}[$i] == $targets->[$targetindex] ){
						push (@{$gamedata->{players}{$effectcontroller }{hand}},    splice(@{$gamedata->{players}{$targetcontroller}{hand}}, $i, 1));
						$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `draws`) VALUES(?, ?)", undef, ($gamedata->{players}{$targetcontroller}{playerid}, -$gamedata->{players}{$effectcontroller }{hand}[-1] ));
			
						last;
					}
				}
			}
			$gamedata->{objects}{$targets->[$targetindex]}{owner}=$effectcontroller;
		}
			my $card = $gamedata->{players}{$effectcontroller }{hand}[-1];
			$gamedata->{objects}{$card}{zone}="hand";
			my $objectstring = "$card:".to_json($gamedata->{objects}{$card});
            $dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, ($gamedata->{players}{$effectcontroller}{playerid}, $objectstring ));
	
			$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `draws`) VALUES(?, ?)", undef, ($gamedata->{players}{$effectcontroller}{playerid}, $gamedata->{players}{$effectcontroller }{hand}[-1] ));
			
	}
	if (lc($effecttype) eq "extrabattlethisturn"){
        debuglog("EXTRA BATTLES! for $targets->[$targetindex]");
        if ($effecttarget eq "target$targetindex"){
            debuglog("$effectmod1 EXTRA BATTLES! for $targets->[$targetindex]");
			$gamedata->{objects}{$targets->[$targetindex]}{battlesthisturn} += $effectmod1;
		}
	}
	if (lc($effecttype) eq "destroy"){
		if ($effecttarget eq "target$targetindex"){
			$gamedata->{objects}{$targets->[$targetindex]}{Health}= 0;
		}
		
	}
	if ($effecttype eq "extraplay"){
		if ($effecttarget eq "currentplayer"){
			debuglog("Bonus to plays remaining ".$effectmod1);
			$gamedata->{playsremaining}+=$effectmod1;
		}
	}
	if ($effecttype eq "Negate"){
		if ($effecttarget eq "self" or $effecttarget eq "target$targetindex"){
			my $keyword;
			
			$gamedata->{objects}{$targets->[$targetindex]}{"keyword"}{$effectmod1}=-1;
			
			my $objectstring = "$targets->[$targetindex]:".to_json($gamedata->{objects}{ $targets->[$targetindex]});
			$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0,  $objectstring ));
						
		}
	}
	if (lc($effecttype) eq "keyword"){
		if ($effecttarget eq "self" or $effecttarget eq "target$targetindex"){
			my $keyword;
			my $amount;
			if ($effectmod1=~/(.*?) (\d+)/i){
				$keyword = $1;
				$amount = $2;
			}else {
				$keyword = $effectmod1;
				$amount = 1;
			}
			#less than 0 prevents us from gaining keyword
			if (checkkeyword($keyword, $targets->[$targetindex]) >= 0 ) {
				$gamedata->{objects}{$targets->[$targetindex]}{"keyword"}{$keyword}+=$amount;
			}
			debuglog(Data::Dumper::Dumper($targets->[$targetindex], $gamedata->{objects}{$targets->[$targetindex] } ));
			if ($gamedata->{objects}{$targets->[$targetindex]}{zone} eq "play"){
				my $objectstring = "$targets->[$targetindex]:".to_json($gamedata->{objects}{ $targets->[$targetindex]});
				$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0,  $objectstring ));
			}
			if ($gamedata->{objects}{$targets->[$targetindex]}{zone} eq "hand"){
				my $objectstring = "$targets->[$targetindex]:".to_json($gamedata->{objects}{ $targets->[$targetindex]});
				$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, ($gamedata->{players}{$effectcontroller}{playerid},  $objectstring ));
			}
		}
	}
	if ($effecttype eq "Silence"){
		if ($effecttarget eq "self" or $effecttarget eq "target$targetindex"){
			foreach my $keyword (keys %{$gamedata->{objects}{$targets->[$targetindex] }{"keyword"}}) { 
				next unless ($keyword);
				$gamedata->{objects}{$targets->[$targetindex] }{"keyword"}{$keyword}=-1;
			}
			my $cardid = $gamedata->{objects}{$targets->[$targetindex] }{"CardId"};
			$gamedata->{objects}{$targets->[$targetindex] }{Attack} = $allcards->{$cardid}{Attack};
			$gamedata->{objects}{$targets->[$targetindex] }{maxhealth} = $allcards->{$cardid}{Health};
			if ($gamedata->{objects}{$targets->[$targetindex] }{Health} > $allcards->{$cardid}{Health}){
				$gamedata->{objects}{$targets->[$targetindex] }{Health} = $allcards->{$cardid}{Health};
			}
			$gamedata->{objects}{$targets->[$targetindex] }{triggers} = [];
			$gamedata->{objects}{$targets->[$targetindex] }{activated} = "";
			$gamedata->{objects}{$targets->[$targetindex] }{Text} = "";
			my $objectstring = "$targets->[$targetindex]:".to_json($gamedata->{objects}{ $targets->[$targetindex]});
			$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0,  $objectstring ));
						
		}
	}
	if ($effecttype eq "Quiet"){
		#lesser silence for metasculpt
		foreach my $keyword (keys %{$gamedata->{objects}{$targets->[$targetindex] }{"keyword"}}) { 
			next unless ($keyword);
			$gamedata->{objects}{$targets->[$targetindex] }{"keyword"}{$keyword}=-1;
		}
		$gamedata->{objects}{$targets->[$targetindex] }{triggers} = [];
		$gamedata->{objects}{$targets->[$targetindex] }{activated} = "";
		$gamedata->{objects}{$targets->[$targetindex] }{Text} = "";
		$gamedata->{static}{$targets->[$targetindex] }= [];
		
	}
	if ($effecttype eq "levelinhand") {
		if ($gamedata->{"objects"}{$targets->[$targetindex]}{"levelsto"} == 0 ){
			return;
		}
		my $new= createobject( $gamedata->{"objects"}{$targets->[$targetindex]}{"levelsto"}, $targetcontroller, 0);
		
		$gamedata->{"objects"}{$new}{"zone"}="hand";
		$gamedata->{"objects"}{$targets->[$targetindex] }{"zone"}="graveyard";
		push @{$gamedata->{players}{$targetcontroller}{hand}}, $new;
		for (my $i=0; $i<=@{$gamedata->{players}{$targetcontroller }{hand}}; $i++){
            if ($gamedata->{players}{$targetcontroller }{hand}[$i] == $targets->[$targetindex]){
                splice(@{$gamedata->{players}{$targetcontroller }{hand}}, $i, 1);
                last;
            }
        }
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `draws`) VALUES(?, ?)", undef, ($gamedata->{players}{$targetcontroller}{playerid}, -$targets->[$targetindex] ));
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `draws`) VALUES(?, ?)", undef, ($gamedata->{players}{$targetcontroller}{playerid}, $new ));
		 my $objectstring = "$new:".to_json($kfgameshared::gamedata->{objects}{ $new });
		 $kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0, $objectstring ));
            
		
		
	}
	if ($effecttype eq "Discard") {
		
		$gamedata->{objects}{$targets->[$targetindex]}{"zone"}="discard";
		my $player = $gamedata->{objects}{ $targets->[$targetindex] }{"owner"};
		
		for (my $i=0; $i<@{$gamedata->{players}{$player }{hand}}; $i++){
            if ($gamedata->{players}{$player }{hand}[$i] == $targets->[$targetindex]){
                splice(@{$gamedata->{players}{$player }{hand}}, $i, 1);
                last;
            }
        }
        push @{$gamedata->{players}{$player}{discard}}, $targets->[$targetindex];
        
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `draws`) VALUES(?, ?)", undef, ($gamedata->{players}{$player}{playerid}, -$targets->[$targetindex] ));

	}
	
	if ($effecttype eq "DiscardDownTo") {
        my $player;
        if ($effecttarget eq "owner"){
            debuglog("Targetting owner: ".$gamedata->{objects}{ $targets->[$targetindex] }{"owner"});
            $player = $gamedata->{objects}{ $targets->[$targetindex] }{"owner"};
		}else {
            if ($gamedata->{objects}{ $targets->[$targetindex] }{"owner"} == 1){
                $player = 2;
            }else {
                $player = 1;
            }
        }
        my $z=0;
		while (@{$gamedata->{players}{$player}{hand}} > $effectmod1 && $z<=200){
            $z++;
            my $cardindex = int rand (@{$gamedata->{players}{$player}{hand}});
            
            my $cardid= $gamedata->{players}{$player}{hand}[$cardindex];
            debuglog("discarding: $cardindex, $cardid, ".scalar @{$gamedata->{players}{$player}{hand}});
		
            $gamedata->{objects}{$cardid}{"zone"}="discard";
            splice(@{$gamedata->{players}{$player }{hand}}, $cardindex, 1);
            
            push @{$gamedata->{players}{$player}{discard}}, $cardid;
        
            $dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `draws`) VALUES(?, ?)", undef, ($gamedata->{players}{$player}{playerid}, -$cardid ));
        }
	}
	
	
	if ($effecttype eq "level") {
		if ($gamedata->{"objects"}{ $targets->[$targetindex] }{"levelsto"} == 0 ){
			return;
		}
		my $new= createobject( $gamedata->{"objects"}{$targets->[$targetindex]}{"levelsto"}, $targetcontroller, 0);
		
		$gamedata->{"objects"}{$new}{"zone"}="discard";
		push @{$gamedata->{players}{$effectcontroller}{discard}}, $new;
		$gamedata->{"objects"}{$targets->[$targetindex]}{zone}="graveyard";
		for (my $i=0; $i<@{$gamedata->{players}{$effectcontroller }{hand}}; $i++){
            if ($gamedata->{players}{$effectcontroller }{hand}[$i] == $targets->[$targetindex]){
                splice(@{$gamedata->{players}{$effectcontroller }{hand}}, $i, 1);
                last;
            }
        }
         my $objectstring = "$new:".to_json($kfgameshared::gamedata->{objects}{ $new });
		 $kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, ($gamedata->{players}{$effectcontroller}{playerid}, $objectstring ));
        
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `draws`) VALUES(?, ?)", undef, ($gamedata->{players}{$effectcontroller}{playerid}, -$targets->[$targetindex] ));
	}
	if (lc($effecttype) eq "heal") {
		if ($effectmod1 =~/(\d+)-(\d+)/){
			my $result=int(rand($2-$1))+$1;
			$effectmod1=$result;
		}
		if ($effecttarget eq "controller"){
			debuglog("healing our controller - $targetcontroller - $effectcontroller");
			$gamedata->{players}{ $effectcontroller }{life}+=$effectmod1;
			checktriggers("healed",  $gamedata->{players}{$effectcontroller } );
			my $healthstring="1:$kfgameshared::gamedata->{players}{1}{life};2:$kfgameshared::gamedata->{players}{2}{life}";
			$kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, life) VALUES(?, ? )", undef, (0, $healthstring ) );
		}
		if ($effecttarget eq "opponent"){
			my $opp = 1;
			if ($effectcontroller == 1){
				$opp=2;
			}
			$gamedata->{players}{$opp}{life}+=$effectmod1;
			checktriggers("healed",  $gamedata->{players}{$opp} );
			my $healthstring="1:$kfgameshared::gamedata->{players}{1}{life};2:$kfgameshared::gamedata->{players}{2}{life}";
			$kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, life) VALUES(?, ? )", undef, (0, $healthstring ) );
		}
		
   
		if ($effecttarget eq "target$targetindex"){
			$kfgameshared::gamedata->{objects}{ $targets->[$targetindex] }{Health}+= $effectmod1;
			if ($kfgameshared::gamedata->{objects}{ $targets->[$targetindex] }{Health} > $kfgameshared::gamedata->{objects}{ $targets->[$targetindex] }{maxhealth}){
				$kfgameshared::gamedata->{objects}{ $targets->[$targetindex] }{Health} = $kfgameshared::gamedata->{objects}{ $targets->[$targetindex] }{maxhealth};
			}
			my $objectstring = "$targets->[$targetindex]:".to_json($gamedata->{objects}{$targets->[$targetindex]});
			$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`,  `object`) VALUES(?, ? )", undef, (0,  $objectstring ));
		}
		
							
		
	}
	if ($effecttype eq "Attackplus" or $effecttype eq "statplus"){
		my $object=0;
		
		if ($effecttarget eq "self" or $effecttarget eq "target$targetindex"){
			$gamedata->{objects}{$targets->[$targetindex]}{Attack} += $effectmod1;
			$object=$targets->[$targetindex];
		}
		if ($effecttarget eq "trigger"){
			$gamedata->{objects}{$targets->[1]}{Attack} += $effectmod1;
			$object=$targets->[1];
		}
		my $objectstring = "$object:".to_json($gamedata->{objects}{$object});
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0, $objectstring ));
	}
	if ($effecttype eq "Healthplus" or $effecttype eq "statplus"){
		my $object=0;
		if ($effecttarget eq "self" or $effecttarget eq "target$targetindex"){
			$gamedata->{objects}{$targets->[$targetindex]}{Health} += $effectmod1;
			$gamedata->{objects}{$targets->[$targetindex]}{maxhealth} += $effectmod1;
			$object=$targets->[$targetindex];
		}
		if ($effecttarget eq "trigger"){
			$gamedata->{objects}{$targets->[1]}{Health} += $effectmod1;
			$gamedata->{objects}{$targets->[1]}{maxhealth} += $effectmod1;
			$object=$targets->[1];
		}
		
		my $objectstring = "$object:".to_json($gamedata->{objects}{$object});
	$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0, $objectstring ));
	}
	
	if ($effecttype eq "stats"){
		
		if ($effecttarget eq "self" or $effecttarget eq "target$targetindex"){
			statadjust($targets->[$targetindex], $effectmod1);
		}
		if ($effecttarget eq "trigger"){
			
			statadjust($targets->[1], $effectmod1);
		}
							
	}
	if (lc($effecttype) eq "draw"){
		if ($effecttarget eq "controller"){
			drawcard($effectcontroller, $effectmod1);
		}
		if ($effecttarget eq "opponent"){
			my $opp = 1;
			if ($effectcontroller == 1){
				$opp=2;
			}
			drawcard($opp, $effectmod1);
		}
	}
	if (lc($effecttype) eq "drag"){
        my $object = $targets->[$targetindex];
        if ($object =~/l(\d)/i){
            $object = $gamedata->{lane}{$effectcontroller}{$1};
        }elsif ( $object =~/ol(\d)/i) {
            my $opp = 1;
            if ($effectcontroller == 1){
                $opp = 2;
            }
            $object = $gamedata->{lane}{$opp}{$1};
        }
        my $lane=0;
        if ($effectmod1 =~/target(\d+)/i){
            $lane = $targets->[$1];
            if ($lane =~/l(\d)/) {
                $lane = $1;
            }
            if ($lane =~/ol(\d)/) {
                $lane = $1;
            }
            
        }else {
            return;
        }
        if ($object and $lane){
             my $oldlane = $gamedata->{objects}{$object}{lane};
             my $side = $gamedata->{objects}{$object}{owner};
             if ($gamedata->{lane}{$side}{$lane} > 0 ){
                debuglog("Lane not empty!");
                return;
             }
             $gamedata->{lane}{$side}{ $oldlane } = 0;
             $gamedata->{lane}{$side}{ $lane } = $object;
             $gamedata->{objects}{$object}{lane} = $lane;
             my $objectstring = "$object:".to_json($gamedata->{objects}{$object} );
             $dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `lane`, `object`) VALUES(?, ?, ? )", undef, (0, "$side:$oldlane:0;$side:$lane:$object", $objectstring ));
             my $opp = 1;
             if ($side == 1){
                $opp = 2;
             }
             checktriggers("Flank", $gamedata->{objects}{$object}, {}, $gamedata->{objects}{ $gamedata->{lane}{$opp}{$lane} } );
        }
        
        
	}
	if (lc($effecttype) eq "move"){
        
	
        if ($effecttarget eq "emptylane" ) {
            debuglog("Attempting to move! $targets->[$targetindex] ".Data::Dumper::Dumper($targets));
            my $lane=0;
            if ($targets->[$targetindex] =~/l(\d)/) {
                $lane = $1;
            }
            if ($targets->[$targetindex] =~/o(\d)/) {
                $lane = $1;
            }
            if ($lane){
                debuglog("lane is defined, moving to $lane");
                my $object = $variables->{source};
                my $oldlane = $gamedata->{objects}{$object}{lane};
                my $controller = $gamedata->{objects}{$object}{owner};
                $gamedata->{lane}{$controller}{ $oldlane } = 0;
                $gamedata->{lane}{$controller}{ $lane } = $object;
                $gamedata->{objects}{$object}{lane} = $lane;
                my $objectstring = "$gamedata->{lane}{$controller}{$lane}:".to_json($gamedata->{objects}{$object} );
                $dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `lane`, `object`) VALUES(?, ?, ? )", undef, (0, "$controller:$oldlane:0;$controller:$lane:$object", $objectstring ));
                checktriggers("Flank", $gamedata->{objects}{$object}, {}, $gamedata->{objects}{ $gamedata->{lane}{$opp}{$lane} } );
            }
        }
		if ($effecttarget eq "opposingCreature"){
			my $lane = $gamedata->{objects}{$targets->[$targetindex]}{lane};
			if ($gamedata->{lane}{$opp}{$lane}>0 and $lane >0){
				if ($effectmod1 eq "randomenemylane"){
					my $target = randomemptylane($opp);
					if ($target>0){
						$gamedata->{lane}{$opp}{$target}=$gamedata->{lane}{$opp}{$lane};
						$gamedata->{lane}{$opp}{$lane} = 0;
						$gamedata->{objects}{ $gamedata->{lane}{$opp}{$lane}}{lane} = $target;
						
						#$gameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `lane`) VALUES(?, ?)", undef, (0, "$opp:$lane:0;$opp:$target:$gamedata->{lane}{$opp}{$target}"));
						my $objectstring = "$gamedata->{lane}{$opp}{$lane}:".to_json($gamedata->{objects}{$gamedata->{lane}{$opp}{$lane}});
						$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `lane`, `object`) VALUES(?, ?, ? )", undef, (0, "$opp:$lane:0;$opp:$target:$gamedata->{lane}{$opp}{$target}", $objectstring ));
                        checktriggers("Flank", $gamedata->{objects}{$gamedata->{lane}{$opp}{$lane}}, {}, $gamedata->{objects}{ $gamedata->{lane}{$effectcontroller}{$target} } );
					}
				}
			}
		}
							
	}
	if (lc($effecttype) eq "replace"){ 
		my $targetlane = $gamedata->{objects}{$targets->[$targetindex]}{lane};
		$gamedata->{objects}{$targets->[$targetindex]}{zone}="Replaced";
		my $object = createobject($effectmod1, $gamedata->{objects}{$targets->[$targetindex]}{owner}, $targetlane );
		$gamedata->{lane}{ $gamedata->{objects}{ $targets->[$targetindex] }{owner} }{$targetlane}=$object;
		$gamedata->{objects}{$object}{ss}=1;
		my $objectstring = "$object:".to_json($gamedata->{objects}{$object});
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `lane`, `object`) VALUES(?, ?, ? )", undef, (0, "$gamedata->{objects}{$targets->[$targetindex]}{owner}:$targetlane:$object", $objectstring ));
		kfgameshared::checktriggers("Creaturetrained", $kfgameshared::gamedata->{objects}{$object}, {Forged => 0});
			
	}
	if (lc($effecttype) eq "spawn"){ 
		if ($effecttarget eq "AllUnopposedEnemies"){
			foreach my $lane (1..5){
				if ($gamedata->{lane}{$opp}{$lane} > 0 and $gamedata->{lane}{$effectcontroller}{$lane} == 0){
					my $object =  createobject($effectmod1, $effectcontroller, $lane );
					$gamedata->{lane}{$effectcontroller}{$lane}=$object;
					$gamedata->{objects}{$object}{ss}=1;
					
					my $objectstring = "$object:".to_json($gamedata->{objects}{$object});
					$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `lane`, `object`) VALUES(?, ?, ? )", undef, (0, "$effectcontroller:$lane:$object", $objectstring ));
					kfgameshared::checktriggers("Creaturetrained", $kfgameshared::gamedata->{objects}{$object}, {Forged => 0});
   
				}
			}
		}
		if ($effecttarget eq "randomemptylane"){
			#find all empty lanes so we can pick one at random
			if ($effectmod1 =~/target(\d)/i){
                $effectmod1 = $gamedata->{objects}{$targets->[$1]}{CardId};
			}
			debuglog("we are $effectcontroller and spawning something( $effectmod1 ) in a random lane. $gamedata->{objects}{$targets->[0]}{owner}");
			my $targetlane = randomemptylane( $effectcontroller  );
			if ( $targetlane > 0){
				my $object = createobject($effectmod1, $effectcontroller, $targetlane );
				$gamedata->{lane}{$effectcontroller}{$targetlane}=$object;
				$gamedata->{objects}{$object}{ss}=1;
				my $objectstring = "$object:".to_json($gamedata->{objects}{$object});
				$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `lane`, `object`) VALUES(?, ?, ? )", undef, (0, "$effectcontroller:$targetlane:$object", $objectstring ));
				debuglog("CHECKING CREATURE TRAINED TRIGGER!");
				kfgameshared::checktriggers("Creaturetrained", $gamedata->{objects}{$object}, {Forged => 0} );
			}else {
                debuglog("we're out of lanes!");
			}
		}
		if ($effecttarget eq "samelane"){
            my $targetlane = $gamedata->{objects}{$targets->[$targetindex]}{lane};
            
				my $object = createobject($effectmod1, $effectcontroller, $targetlane );
				$gamedata->{lane}{$effectcontroller}{$targetlane}=$object;
				$gamedata->{objects}{$object}{ss}=1;
				my $objectstring = "$object:".to_json($gamedata->{objects}{$object});
				$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `lane`, `object`) VALUES(?, ?, ? )", undef, (0, "$effectcontroller:$targetlane:$object", $objectstring ));
				kfgameshared::checktriggers("Creaturetrained", $kfgameshared::gamedata->{objects}{$object}, {Forged => 0});
			
		}
		if ($effecttarget eq "emptylane"){
			
            my $targetlane = $targets->[$targetindex];
            debuglog("spawning to $targetlane, $effectmod1");
            my $object;
            if ( $targetlane =~s /ol//i){
                
				$object = createobject($effectmod1, $opp, $targetlane );
				$gamedata->{lane}{$opp}{$targetlane}=$object;
				$gamedata->{objects}{$object}{ss}=1;
				my $objectstring = "$object:".to_json($gamedata->{objects}{$object});
				$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `lane`, `object`) VALUES(?, ?, ? )", undef, (0, "$opp:$targetlane:$object", $objectstring ));
			}
            if ( $targetlane =~s /l//i){
				$object = createobject($effectmod1, $effectcontroller, $targetlane );
				$gamedata->{lane}{$effectcontroller}{$targetlane}=$object;
				$gamedata->{objects}{$object}{ss}=1;
				my $objectstring = "$object:".to_json($gamedata->{objects}{$object});
				$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `lane`, `object`) VALUES(?, ?, ? )", undef, (0, "$effectcontroller:$targetlane:$object", $objectstring ));
			}
			kfgameshared::checktriggers("Creaturetrained", $kfgameshared::gamedata->{objects}{$object}, {Forged => 0});
		}
	}
	if (lc($effecttype) eq "damage"){
		if ($effectmod1 =~/(\d+)-(\d+)/){
			my $result=int(rand($2-$1))+$1;
			$effectmod1=$result;
		}
		if ($effecttarget eq "AllEnemyCreatures"){
			foreach my $lane (1..5){
				if ($gamedata->{lane}{$opp}{$lane}>0){
					applydamage($gamedata->{lane}{$opp}{$lane}, $effectmod1, 2);
					 my $objectstring = "$kfgameshared::gamedata->{lane}{$opp}{$lane}:".to_json($kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{$opp}{$lane} });
					$kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0, $objectstring ));
            
				}	
			}
		}
		if ($effecttarget eq "self" or $effecttarget eq "target$targetindex"){
			if ($targets->[$targetindex] eq "opp" or $targets->[$targetindex] eq "self"){
			}else {
			applydamage($targets->[$targetindex], $effectmod1, 2);
			}
		}
		if ($effecttarget eq "opponent" or ( $effecttarget eq "target$targetindex" and $targets->[$targetindex] eq "opp"  )  ){
			
			$gamedata->{players}{$opp}{life} -= $effectmod1;
		}
		if ($effecttarget eq "controller" or ( $effecttarget eq "target$targetindex" and $targets->[$targetindex] eq "self" ) ){
			$gamedata->{players}{$effectcontroller}{life} -= $effectmod1;
		}
		 my $healthstring="1:$kfgameshared::gamedata->{players}{1}{life};2:$kfgameshared::gamedata->{players}{2}{life}";
		$kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, life) VALUES(?, ? )", undef, (0, $healthstring ) );
    
		
	}
	if ($effecttype =~/AddTrigger/i){
		
		if ( defined $gamedata->{objects}{$targets->[$targetindex]}{newtriggers} ){
			push(@{$gamedata->{objects}{$targets->[$targetindex]}{newtriggers}}, $effectmod1);
		}else {
			$gamedata->{objects}{$targets->[$targetindex]}{newtriggers}=[];
			push(@{$gamedata->{objects}{$targets->[$targetindex]}{newtriggers}}, $effectmod1);
		}
		
	}
	
}
sub shufflediscardintodeck {
	my $weare=shift;
	my @stays;
	my @changedobjects;
	foreach my $card (@{$kfgameshared::gamedata->{players}{$weare }{discard}}){
		if ($gamedata->{objects}{$card}{level}<= $kfgameshared::gamedata->{players}{$weare}{level} )  {
			$kfgameshared::gamedata->{objects}{$card}{zone}="deck";
			push @{$kfgameshared::gamedata->{"deck$weare"}}, $card;
			push (@changedobjects, $card);
		}else {
			push @stays, $card;
		}
    }
    @changedobjects= shuffle(@changedobjects);
    
	foreach my $new (@changedobjects){
		my $objectstring = "$new:".to_json($kfgameshared::gamedata->{objects}{ $new });
		$kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, ($gamedata->{players}{$weare}{playerid}, $objectstring ));
    }
    @{$kfgameshared::gamedata->{"deck$weare"}} =  shuffle(@{$kfgameshared::gamedata->{"deck$weare"}});
        
    $kfgameshared::gamedata->{players}{$weare}{discard}=\@stays;
        
}

sub removeeffect2 {
	my $object=shift;
	my $data=shift;
	
	debuglog("REMOVING2! $data->{effecttype} - $data->{effecttarget} - $data->{effectmod1} from $object ");
	if (lc($data->{effecttype}) eq "keyword") {
		debuglog("Removing keyword!");
		my $keyword;
		my $amount;
		if ($data->{effectmod1}=~/(.*?) (\d+)/i){
			$keyword = $1;
			$amount = $2;
		}else {
			$keyword = $data->{effectmod1};
			$amount = 1;
		}
		$amount = 0-$amount;
		if (checkkeyword($keyword, $object) >= 0  ) {
				$gamedata->{objects}{$object}{"keyword"}{$keyword}+=$amount;
				if (checkkeyword($keyword, $object) == 0){
					delete $gamedata->{objects}{$object}{"keyword"}{$keyword};
					debuglog("removing this keyword completely");
				}else {
					debuglog("still has: ".checkkeyword($keyword, $object) ." $keyword left");
				}
		}
		my $objectstring = "$object:".to_json($gamedata->{objects}{ $object });
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0,  $objectstring ));
		debuglog("REMOVED KEYWORD $keyword by $amount\n\n");
			
	}
	if ($data->{effecttype} =~ /AddTrigger/i){
        
        my $i=0;
        while ($i < @{$gamedata->{objects}{$object}{triggers}}){
            if ($gamedata->{objects}{$object}{triggers}[$i] == $data->{effectmod1}){
                splice(@{$gamedata->{objects}{$object}{triggers}}, $i, 1);
                last;
            }
        }
	}
	if ($data->{effecttype} eq "Attackplus" or $data->{effecttype} eq "statplus"){
        $gamedata->{objects}{$object}{Attack} -= $data->{effectmod1};
        	my $objectstring = "$object:".to_json($gamedata->{objects}{ $object });
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0,  $objectstring ));	
	}
	if ($data->{effecttype} eq "Healthplus" or $data->{effecttype} eq "statplus"){
        $gamedata->{objects}{$object}{Health} -= $data->{effectmod1};
        $gamedata->{objects}{$object}{maxhealth} -= $data->{effectmod1};
        	my $objectstring = "$object:".to_json($gamedata->{objects}{ $object });
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0,  $objectstring ));	
	}
	if ($data->{effecttype} eq "stats"){
		my $stats  = $data->{effectmod1};
		my @stats = split("/", $stats);
		debuglog("stat removal for object $object : $stats $object".ref $object);		
		my $mod = substr($stats[0], 0, 1);
	
		my $amount = substr($stats[0], 1);
		if ($mod eq "+"){
			$gamedata->{objects}{$object}{Attack} += -$amount;
		}elsif ($mod eq "-"){
			$gamedata->{objects}{$object}{Attack} -= -$amount;
		}else {
			$gamedata->{objects}{$object}{Attack} += -$amount;
		}
		
		$mod = substr($stats[1], 0, 1);
	
		$amount = substr($stats[1], 1);
		if ($mod eq "+"){
			$gamedata->{objects}{$object}{Health} += -$amount;
			$gamedata->{objects}{$object}{maxhealth} += -$amount;
		}elsif ($mod eq "-"){
			$gamedata->{objects}{$object}{Health} -= -$amount;
			$gamedata->{objects}{$object}{maxhealth} -= -$amount;
		}
		
			my $objectstring = "$object:".to_json($gamedata->{objects}{ $object });
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0,  $objectstring ));				
	}
	
	

}

sub applydamage {
	my $object = shift;
	my $damage=shift;
	
	if ($damage <=0){
		return 0;
	}
	if (my $armor= checkarmor( $object)> 0){
                if ($armor > $damage){
                    $kfgameshared::gamedata->{objects}{$object }{armorthisturn} += $damage;
                    $damage=0;
                }else {
                    $damage -= $armor;
                    $kfgameshared::gamedata->{objects}{$object }{armorthisturn} += $armor;
                }
				
			}
        
        if ($damage>=0){
            kfgameshared::checktriggers("Damagereceived", $object, {Damage=> $damage });
            $gamedata->{objects}{$object}{Health}-= $damage;
        }
	
	
	
	my $objectstring = "$object:".to_json($gamedata->{objects}{ $object });
        $dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0, $objectstring ));
           
	 
}



sub statadjust {
	my $object = shift;
	my $stats = shift;
	my $reverse = shift;
	my @stats = split("/", $stats);
	if (ref $object eq "HASH"){
		debuglog("Is a hash, making a id");
		$object = $object->{id};
	}
	
	debuglog("stat adjust for object $object : $stats ".ref $object);		
	my $mod = substr($stats[0], 0, 1);
	
	my $amount = substr($stats[0], 1);
	if ($mod eq "+"){
		$gamedata->{objects}{$object}{Attack} += $amount;
	}elsif ($mod eq "-"){
		$gamedata->{objects}{$object}{Attack} -= $amount;
	}elsif ($mod eq "="){
		$gamedata->{objects}{$object}{Attack} = $amount;
	}else {
		$gamedata->{objects}{$object}{Attack} += $amount;
	}
								
 	$mod = substr($stats[1], 0, 1);
	
	$amount = substr($stats[1], 1);
	if ($mod eq "+"){
		$gamedata->{objects}{$object}{Health} += $amount;
		$gamedata->{objects}{$object}{maxhealth} += $amount;
	}elsif ($mod eq "="){
		$gamedata->{objects}{$object}{Health} = $amount;
		$gamedata->{objects}{$object}{maxhealth} = $amount;
	}elsif ($mod eq "-"){
		$gamedata->{objects}{$object}{Health} -= $amount;
		$gamedata->{objects}{$object}{maxhealth} -= $amount;
	}
	
	
	my $objectstring = "$object:".to_json($gamedata->{objects}{$object});
	$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0, $objectstring ));
														
	 
}

sub discard {
    my $weare=shift;
	my $number = (shift or 0);
#	warn "discard called";
	foreach my $card (@{$gamedata->{players}{$weare }{hand}} ) {
#        warn "checking if we should discard $card<BR>";
        
        if (!$number or $number == $card){
 #           warn "discarding cards!";
            
            $gamedata->{objects}{$card}{zone}="discard";
            push (@{$gamedata->{players}{ $weare }{discard}}, $card);
            my $objectstring = "$card:".to_json($gamedata->{objects}{$card});
            $dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, ($gamedata->{players}{$weare}{playerid}, $objectstring ));
	
            $dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `draws`) VALUES(?, ?)", undef, ($gamedata->{players}{$weare}{playerid}, -$card ));
            
		}
	}
	if (!$number) {
        $gamedata->{players}{$weare}{hand}=[];
	}else {
        for (my $i=0; $i<=@{$gamedata->{players}{$weare }{hand}}; $i++){
            if ($gamedata->{players}{$weare }{hand}[$i] == $number){
                splice(@{$gamedata->{players}{$weare }{hand}}, $i, 1);
                last;
            }
        }
	}
		
}
sub drawcard {
	my $weare=shift;
	my $number = (shift or 1);
	
	while ($number >0){
		if (@{$gamedata->{"deck$weare"}}<= 0 ){
			shufflediscardintodeck($weare);
			logmessage("$gamedata->{players}{$weare}{name} shuffles their discard into deck. (no cards were in deck)");
		}
			push(@{$gamedata->{players}{$weare }{hand}}, pop @{$gamedata->{"deck$weare"}});
			my $card = $gamedata->{players}{$weare }{hand}[-1];
			$gamedata->{objects}{$card}{zone}="hand";
			my $objectstring = "$card:".to_json($gamedata->{objects}{$card});
		   $dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, ($gamedata->{players}{$weare}{playerid}, $objectstring ));
	
			$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `draws`) VALUES(?, ?)", undef, ($gamedata->{players}{$weare}{playerid}, $gamedata->{players}{$weare }{hand}[-1] ));
			
		
		$number --;
		
	}
}
sub randomemptylane {
	my $who=shift;
	my @lanes = findemptylanes($who);
	if (int @lanes > 0 ){
		return $lanes[ int rand(@lanes) ] ;
	}else {
		return 0;
	}
	
}

sub findemptylanes {
	my $who=shift;
	my @emptylanes;
	foreach my $i (1..5) {
		if ($gamedata->{lane}{$who}{$i}==0){
			push (@emptylanes, $i);
		}
	}
	return @emptylanes;
}


sub triggercompare {
	my $self =shift;
	my $target= shift;
	my $equation1 = shift;
	my $equationcomp = shift;
	my $equation2 = shift;
	my $variables = shift;
	my $secondobject = shift;
	
# 	debuglog("variables in triggercompare(start): ".Data::Dumper::Dumper($variables));
# 	debuglog(caller);
    
    my $var1="";
	my $var2="";
	
	if (!defined($equationcomp) or length ($equationcomp) == 0 ) {
		
		return 1;
	}
	debuglog(caller);
    if (defined($self) && defined $target && defined $equationcomp && defined $equation2){
        debuglog("$self, $target, $equation1, $equationcomp, $equation2");
    }
	my @results = split(/\./, $equation1);
	if ($results[0] eq "self"){
		if ($results[1] eq "opposed"){
			my $lane = $self->{lane};
			my $otherlane=1;
			if ($self->{owner} == 1){
				my $otherlane=2;
			}
			if ($gamedata->{lane}{$otherlane}{$lane}>0 ) {
				$var1=1;
			}else {
				$var1=0;
			}
			
		}elsif ($results[1] eq "controller"){
			
			$var1=$gamedata->{players}{$self->{owner} }{$results[2] };
		}elsif ($results[1] eq "lowestenemy"){
            my $lowest = 9999;
            my $opp = 1;
            if ($self->{owner} == 1){
                $opp = 2;
            }
            for my $lane (1..5){
                if ($gamedata->{lane}{$opp}{$lane} > 0 ){
                    if ($gamedata->{objects}{ $gamedata->{lane}{$opp}{$lane} }{$results[2]} < $lowest){
                        $lowest = $gamedata->{objects}{ $gamedata->{lane}{$opp}{$lane} }{$results[2]};
                    }
                }
            }
            $var2 = $lowest;
        
        }elsif ($results[1] eq "lowestinplay"){
            my $lowest = 9999;
            for my $lane (1..5){
                if ($gamedata->{lane}{1}{$lane} > 0 ){
                    if ($gamedata->{objects}{ $gamedata->{lane}{1}{$lane} }{$results[2]} < $lowest){
                        $lowest = $gamedata->{objects}{ $gamedata->{lane}{1}{$lane} }{$results[2]};
                    }
                }
                if ($gamedata->{lane}{2}{$lane} > 0 ){
                    if ($gamedata->{objects}{ $gamedata->{lane}{2}{$lane} }{$results[2]} < $lowest){
                        $lowest = $gamedata->{objects}{ $gamedata->{lane}{2}{$lane} }{$results[2]};
                    }
                }
                
            }
            $var2 = $lowest;
        
        }elsif ($results[1] eq "lanesfilled"){
			my $total=0;
			for my $lane (1..5) {
				if ($gamedata->{lane}{ $self->{owner} }{$lane} > 0){
					$total += 1;
				}
			}
			$var1=$total;
			debuglog("checking lanesfilled, value = $total");
		}elsif ($results[1] eq "factioninhand"){
			my $number=0;
			foreach my $card ( @{$gamedata->{players}{$self->{owner}}{hand}}){
				if ($gamedata->{objects}{$card}{Faction} eq $results[2]){
					$number ++;
				}
			}
			$var1=$number;
		}elsif ($results[1] eq "keyword"){
			$var1=checkkeyword($results[2], $self->{id})
		}else {
			if (!defined $self->{$results[1]}){
				debuglog("Error, not defined in self! ".Data::Dumper::Dumper($self));
				
				return 0;
			}
			$var1=$self->{$results[1]};
		}
	}
	#if ($equation1=~/^target.(.*?)$/){
	if ($results[0] eq "secondobject"){
        if (!defined $gamedata->{objects}{$secondobject}{$results[1]}){
            debuglog("Error, not defined in target! ". $results[1]);
            
            return 0;
        }
        $var1=$gamedata->{objects}{$secondobject}{$results[1]};
	}
	if ($results[0] eq "target"){
		if (!$target){
			debuglog("target is undefined");
		}
		if ($results[1] eq "opposed"){
			my $lane = $target->{lane};
			my $otherlane=1;
			if ($target->{owner} == 1){
				my $otherlane=2;
			}
			if ($gamedata->{lane}{$otherlane}{$lane}>0 ) {
				$var1=1;
			}else {
				$var1=0;
			}
			
		}
		if ($results[1] eq "controller"){
			$var1=$gamedata->{players}{ $target->{owner} }{$results[2] };
		}elsif ($results[1] eq "keyword"){
			$var1 = checkkeyword($results[2], $target->{id});
		}elsif ($results[1] eq "lowestinplay"){
            my $lowest = 9999;
            for my $lane (1..5){
                if ($gamedata->{lane}{1}{$lane} > 0 ){
                    if ($gamedata->{objects}{ $gamedata->{lane}{1}{$lane} }{$results[2]} < $lowest){
                        $lowest = $gamedata->{objects}{ $gamedata->{lane}{1}{$lane} }{$results[2]};
                    }
                }
                if ($gamedata->{lane}{2}{$lane} > 0 ){
                    if ($gamedata->{objects}{ $gamedata->{lane}{2}{$lane} }{$results[2]} < $lowest){
                        $lowest = $gamedata->{objects}{ $gamedata->{lane}{2}{$lane} }{$results[2]};
                    }
                }
                
            }
            $var1 = $lowest;
        
        }else {
			if (!defined $target->{$results[1]}){
				debuglog("Error, not defined in target! ". $results[1]);
				
				return 0;
			}
			$var1=$target->{$results[1]};
		}
		
	}
	if ($results[0] eq "random"){
        $var1 = rand($results[1]);
	}
	
	if ($results[0] eq "variable"){
        debuglog("checking variable $results[1] :".Data::Dumper::Dumper($variables));
        if ($results[1] eq "distance" and !(defined $variables->{distance})){
                debuglog("we're requesting a distance value!");
                if (!defined $self->{lane} or !defined($target->{lane}) ) {
                    $var1=0;
                }else{
                    $var1 = abs($self->{lane} - $target->{lane});
                }
                
        }else {
            if (!defined $variables) {
                $var1=0;
            }else {
                $var1=$variables->{$results[1]};
			}
		}
	}
	
	if ($results[0] eq "core"){
        debuglog(@results);
        if ($results[1] eq "count"){
            debuglog("Checking count of target matches!");
            my ($lane, $olane, $raw, $totalvalidtargets, $variables, $players) = findtargets_revised($gamedata->{turn}, $results[2], $self->{id});
            debuglog("$totalvalidtargets");
            $var1=$totalvalidtargets;
        }else {
            debuglog("Just a normal core value");
            $var1=$gamedata->{$results[1]};
		}
	}
	
	@results = split(/\./, $equation2);
	
	if ($equation2=~/^target.(.*?)$/){
        if (!$target){
			debuglog("target is undefined");
		}
		if ($results[1] eq "opposed"){
			my $lane = $target->{lane};
			my $otherlane=1;
			if ($target->{owner} == 1){
				my $otherlane=2;
			}
			if ($gamedata->{lane}{$otherlane}{$lane}>0 ) {
				$var2=1;
			}else {
				$var2=0;
			}
			
		}
		if ($results[1] eq "controller"){
			$var2=$gamedata->{players}{ $target->{owner} }{$results[2] };
		}elsif ($results[1] eq "lowestinplay"){
            my $lowest = 9999;
            for my $lane (1..5){
                if ($gamedata->{lane}{1}{$lane} > 0 ){
                    if ($gamedata->{objects}{ $gamedata->{lane}{1}{$lane} }{$results[2]} < $lowest){
                        $lowest = $gamedata->{objects}{ $gamedata->{lane}{1}{$lane} }{$results[2]};
                    }
                }
                if ($gamedata->{lane}{2}{$lane} > 0 ){
                    if ($gamedata->{objects}{ $gamedata->{lane}{2}{$lane} }{$results[2]} < $lowest){
                        $lowest = $gamedata->{objects}{ $gamedata->{lane}{2}{$lane} }{$results[2]};
                    }
                }
                
            }
            $var2 = $lowest;
        
        }elsif ($results[1] eq "keyword"){
			$var2 = checkkeyword($results[2], $target->{id});
		}else {
			if (!defined $target->{$results[1]}){
				debuglog("Error, not defined in target! ". $results[1]);
				
				return 0;
			}
			$var2=$target->{$results[1]};
		}

	}
	
	if ($equation2=~/^self.(.*?)$/){
#		debuglog("self " . $1);
#		debuglog(Data::Dumper::Dumper($self));
		$var2=$self->{$1};
	}
	if ($equation2=~/^core.(.*?)$/){
		$var2=$gamedata->{$1};
	}
	if ($equation2=~/^value.(.*?)$/){
		$var2=$1;
	}
	if ($equation1=~/^value.(.*?)$/){
		$var1=$1;
	}
	
	debuglog("$equation1, $equation2");
	debuglog("$var1 $equationcomp $var2 ? ");
	
	if ($equationcomp eq "=" or $equationcomp eq "=="){
		if ($var1 == $var2 ) {
			return 1;
		}else {
			return 0;
		}
	}
	if ($equationcomp eq "eq"){
		if ($var1 eq $var2 ) {
			return 1;
		}else {
			return 0;
		}
	}
	if ($equationcomp eq "ne"){
		if ($var1 ne $var2 ) {
			return 1;
		}else {
			return 0;
		}
	}
	if ($equationcomp eq "con"){
		if ($var1 =~/$var2/i ) {
			
			return 1;
		}else {
			
			return 0;
		}
	}
	if ($equationcomp eq "ncon"){
		if ($var1 =~/$var2/i ) {
			
			return 0;
		}else {
			
			return 1;
		}
	}
	if ($equationcomp eq "<"){
		if ($var1 < $var2 ) {
			return 1;
		}else {
			return 0;
		}
	}
	
	if ($equationcomp eq ">"){
		if ($var1 > $var2 ) {
			return 1;
		}else {
			return 0;
		}
	}
	if ($equationcomp eq "<="){
		if ($var1 <= $var2 ) {
			return 1;
		}else {
			return 0;
		}
	}
	
	if ($equationcomp eq ">="){
		if ($var1 >= $var2 ) {
			return 1;
		}else {
			return 0;
		}
	}
	if ($equationcomp eq "!="){
		debuglog("$var1 != $var2 ? ");
		if ($var1 != $var2 ) {
			return 1;
		}else {
			return 0;
		}
	}
}


sub savegame {
    my $game=shift;
    
    checkstatebased($game);
    
    my $data=Dumper($gamedata);
    $dbh->do("UPDATE `GameData` SET `data` = ? WHERE `gameid` = ?", undef, ($data, $game));

}
sub sendnewmessages{
    my $game=shift;
    my $response;
    my $startmessage= (param("startmessage") or param("lastmessage") );
    if ($startmessage){
        $response->{messages}=$dbh->selectall_arrayref("SELECT * from `GameMessages_$game` WHERE  `messageid` > ? AND (`playerid`= ? or `playerid` = 0) ORDER BY `messageid` ASC", {Slice =>{}}, ($startmessage, $player->{userId}));
    }else{
        $response->{messages}=$dbh->selectall_arrayref("SELECT * from `GameMessages_$game` WHERE `playerid` = ? or `playerid` = 0 ORDER BY `messageid` ASC", {Slice =>{}}, ($player->{userId}));
    }
    #print "Content-Type: Text/JSON\n\n";

	foreach my $row (@{$response->{messages}}){
		foreach my $col (keys %{$row}){
			if (!defined $row->{$col} or length($row->{$col}) == 0) {
				#print "$col -- $row->{$col}<BR>";
				delete($row->{$col});
			}
		}
		delete($row->{playerid});
	}
    return $response->{messages};
}

sub createobject {
	my $basecard=shift;
	my $owner = shift;
	my $lane =(shift or 0);
	unless ($allcards->{$basecard}){
		debuglog( "Card doesn't exists? $basecard");
	}
	my $card= {};
	foreach my $data (keys %{$allcards->{$basecard}} ) {
		$card->{$data} = $allcards->{$basecard}{$data};
	}
	if (!$card->{maxhealth}){
        $card->{maxhealth}=$card->{Health};
	}
	$card->{triggers}=[];
	if ($card->{basetriggers}){	
		@{$card->{triggers}}=split(",", $card->{basetriggers});
	}
	$card->{static}= [];
	if ($card->{basestatic}){
		@{$card->{static}}=split(",", $card->{basestatic});
	}
	
	
	if ($card->{activated}){
        my @activated = split(",", $card->{activated});
        $card->{activated} = [];
        foreach my $active (@activated) {
			push (@{$card->{activated}}, $active);
		}
	}else {
        $card->{activated} = [];
	}
	$card->{keyword}={};
	if ($card->{keywords}){
		my @keywords = split(",", $card->{keywords});
		foreach my $keyword (@keywords) {
			if ($keyword=~s/ (\d+)$//){
				$card->{keyword}{$keyword}=$1;
			}else {
				$card->{keyword}{$keyword}=1;
			}
		}
	}
	
	if (!defined $gamedata->{objects} ){
		$gamedata->{objects}={};
	}
	my $objectnumber = $gamedata->{objectnumber}+1;
	$card->{owner} = $owner;
	$card->{id}=$objectnumber;
	
	if ($lane ){
		$card->{zone} = "play";
		$card->{armorthisturn} = 0;
	}
	$card->{lane}=$lane;
	$card->{battlesthisturn} = $card->{battlesperturn};
	
	$gamedata->{objectnumber}=$objectnumber;
	$gamedata->{objects}{$objectnumber} = $card;
	
	return $objectnumber;
	
	
}

sub checkkeyword {
	my $keyword = shift;
	my $object = shift;
	unless ($object){
		warn "NO OBJECT!";
	}
	if (defined ($gamedata->{objects}{ $object }{"keyword"}{$keyword}) and ($gamedata->{objects}{ $object }{"keyword"}{$keyword} != 0)){
		return $gamedata->{objects}{ $object }{"keyword"}{$keyword};
	}else {
		return 0;
	}
}

sub checkendgame {
	my $winner=0;
	if ($gamedata->{players}{1}{life} <=0 and $gamedata->{players}{1}{life} < $gamedata->{players}{2}{life}){
		#player 1 has lost
		$gamedata->{ended}=2;
		logmessage("$gamedata->{players}{1}{name} has lost the game!");
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `ended`) VALUES(?, ?)", undef, (0, 2));
		$winner=2;
    
	}
	if ($gamedata->{players}{2}{life} <=0 and $gamedata->{players}{2}{life} < $gamedata->{players}{1}{life}){
		#player2 has lost
		$gamedata->{ended}=1;
		logmessage("$gamedata->{players}{2}{name} has lost the game!");
		$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `ended`) VALUES(?, ?)", undef, (0, 1));
		$winner=1;
	}
	if ($winner){
		use LWP::UserAgent;
		use HTTP::Request;
	
		my $userAgent = LWP::UserAgent->new();
		my $request = HTTP::Request->new( POST => "https://kaelari.tech/kfplatform/endgame.cgi" );
		warn "ending game: &game=$game&winner=$winner";
		$request->content("password=ajdkhfaksjfhakdsaflkjhas&game=$game&winner=$winner");
		$request->content_type("application/x-www-form-urlencoded");
		my $response = $userAgent->request($request);
	}
}

sub checkcast {
	my $canplay="";
	my @canplay;
	my $weare=$gamedata->{turn};
	my $opp= 0;
	my $variables;
	if ($weare == 1 ){
		$opp = 2;
	}else {
		$opp=1;
	}
        outer: foreach my $card (@{$gamedata->{players}{$gamedata->{turn} }{hand} }){
		if ($gamedata->{objects}{$card}{CardType} ne "Effect"){
			next;
		}
		
		if ( ($gamedata->{objects}{$card}{cost} > $gamedata->{players}{$gamedata->{turn}}{gold} ) and (checkkeyword("Free", $gamedata->{objects}{$card}) <=0 ) ){
			#we don't have enough actions!                
			next;
		}
		my %threshold;
		foreach my $type (split("",  $gamedata->{objects}{$card}{threshold} ) ) {
            	
			$threshold{$type}+=1;
		}
    
		foreach my $type (keys %threshold){
			if (!defined ($gamedata->{players}{ $gamedata->{turn} }{threshold}{$type}) ) {
				next outer;
			}
			if ($threshold{$type} > $gamedata->{players}{ $gamedata->{turn} }{threshold}{$type}){
				#we don't have threshold!
                    
				next outer;
			}
		}
		my $card2=$card;
                
		my $targets= [{
			}];
		my $lane;
		my $olane;
		
		foreach my $target (split (",",$gamedata->{objects}{$card}{targets} )){
			if (!$target){
				next;
			}
			my $totalvalidtargets=0;
			($lane, $olane, $totalvalidtargets, $variables) = findtargets ($weare, $target, $card);
				
			if ($totalvalidtargets == 0){	
				next outer;
			}
			$targets = [ {
				'text' => $alltargets->{$target}{text},
				l => $lane,
				o => $olane,
			}];
                }
                $card2="$card:".to_json($targets);
		push (@canplay, $card2);
		
	}
        
        
        $canplay=join(";", @canplay);
        if (length ($canplay) == 0){
		$canplay="[]";
        }
        $dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `handplayable`) VALUES(?, ?)", undef, ($player->{userId}, $canplay ));
	$gamedata->{hidden}{$gamedata->{turn}}{handplayable}=$canplay;
	 
}

sub findtargetsallzones {
	my $weare = shift;
	my $target = shift;
	my $targetting = shift;
	my $opp = 1;
	if ($weare == 1) {
		$opp=2;
	}
	my $totalvalidtargets=0;
	my @targets;
	foreach my $card (keys %{$gamedata->{objects}}){
		if (defined $gamedata->{objects}{$card}{zone}){
			#debuglog("Checking $card ".Data::Dumper::Dumper($gamedata->{objects}{$card}));
		}
		if (checktarget($target, $card, $targetting, $weare ) ){
				push (@targets, $card);
				$totalvalidtargets +=1;
			}
	}
	@targets = shuffle(@targets);
	return \@targets, $totalvalidtargets;
}

sub verifytargets {
	my $targetids=shift;
	my $targets = shift;
	my $targetting = shift;
	my $weare = shift;
	my $sourceobject= shift;
	
	my $opp=1;
	if ($weare == 1){
		$opp=2;
	}
	if (ref $targetids ne "ARRAY"){
		debuglog("$targetids is not an array!");
		$targetids =[$targetids];
	}
	my @newtargets;
	my @alltargets;
		
	my $targetdata = $alltargets->{$targetids->[0]};
	debuglog("verifying targets".Data::Dumper::Dumper($targetdata).Data::Dumper::Dumper($targetids).Data::Dumper::Dumper($targets));
	debuglog("Target is ".Data::Dumper::Dumper($targets));
	my $variables;
	my $startindex=0;
	foreach my $targetid (@{$targetids}){
		my $lane;
		my $olane;
		my $raw;
		my $totalvalidtargets;
		my $players;
		my $endindex=$startindex;
		my $variables2;
		
		if ($targetid eq "" || !defined $targetid || $targetid == 0){
            next;
		}
		debuglog("target is: ".$targetid);
		
		debuglog("Target is ".Data::Dumper::Dumper($targets));
		 ($lane, $olane, $raw, $totalvalidtargets, $variables2, $players) = findtargets_revised($gamedata->{turn}, $targetid, $targetting);
		 foreach my $key (keys %{$variables2}){
            $variables->{$key} = $variables2->{$key};
		 }
		 if ($alltargets->{$targetid}{maxtargets}< $totalvalidtargets){
            
			$endindex+=($alltargets->{$targetid}{maxtargets}-1);
		}else {
            $endindex+=$totalvalidtargets-1;
		}
		 debuglog("players is: ".Data::Dumper::Dumper($players));
#  		debuglog(Data::Dumper::Dumper($targets), Data::Dumper::Dumper($lane));
		debuglog("maxtargets: $alltargets->{$targetid}{maxtargets}, endindex: $endindex, startindex, $startindex");
		outer: foreach my $index ($startindex..$endindex ) {
            
			if (!$targets->[$index]){
				next;
			}
			if ($alltargets->{$targetid}{Selector} eq "None" or $alltargets->{$targetid}{Selector} eq "All"){
                debuglog("This is an All target, just use all targets instead of verifying the target we sent");
				next outer;
			}
			debuglog("Target is $targets->[$index]");
			if ($targets->[$index] =~/l(\d)/){
			#this is our lane
				foreach my $valid (@{$lane}){
					debuglog("$valid ? $1");
					if ($1 eq $valid){
						debuglog("This is valid!");
						next outer;
					}
				}
			
			}
			if ($targets->[$index]=~/ol(\d)/){ 
				foreach my $valid (@{$olane}){
					debuglog("olane: $valid ? $1");
					if ($1 eq $valid){
						next outer;
					}
				}
			}	
			if ($targets->[$index]=~/opp/){ 
				if (scalar @{$players} > 0 ){
					next outer;
				}
			}	
			if ($targets->[$index]=~/self/){ 
				if (scalar @{$players} > 0 ){
					next outer;
				}
			}	
			
			if ($targets->[$index]=~/(\d)/){ 
				debuglog("raw". Data::Dumper::Dumper($raw));
				foreach my $valid (@{$raw}){
					if ($targets->[$index] == $valid){
						next outer;
					}
				}
			}
			
			debuglog("Not a valid target! $targetid, $index, $targets->[$index]");
			return \@newtargets, \@alltargets, $variables, 1;
			
		}
		
        foreach my $index ($startindex..$endindex ) {
            debuglog("index: $index of $endindex");
            if ($alltargets->{$targetid}{targettype} ne "lane"){
			
                $a= $targets->[$index];
				next unless ($a);
				my $b;
				if ($a=~/ol(\d)/) {
					$b=$gamedata->{lane}{$opp}{$1};
				}
				elsif ($a=~/l(\d)/) {
					$b=$gamedata->{lane}{$weare}{$1};
				}else {
					$b= $a;
				}
				if ($alltargets->{$targetid}{Selector} ne "All"){
                    debuglog("Need to check a variable here");
                    if (my $tmp = checktarget($targetid, $b, $targetting, $weare)){
                        foreach my $key (keys %{$tmp}){
                            $variables->{$key}=$tmp->{$key};
                        }
                    }
				}
				push @newtargets, $b;
			
	
		
                foreach my $target (@{$lane}){
                    push(@alltargets, $gamedata->{lane}{$weare}{$target});
                }
                foreach my $target (@{$olane}){
                    push(@alltargets, $gamedata->{lane}{$opp}{$target});
                }
                foreach my $target (@{$raw}){
                    push(@alltargets, $target);
                }
            }else {
#             foreach my $a (@{$targets}){
# 				next unless ($a);
# 				push @newtargets, $a;
# 			}
                if ($targets->[$index]){
                    push @newtargets, $targets->[$index];
                }
                foreach my $target (@{$lane}){
                    push(@alltargets, "l$target");
                }
                foreach my $target (@{$olane}){
                    push(@alltargets, "ol$target");
                }
                foreach my $target (@{$raw}){
                    push(@alltargets, $target);
                }
            }
		}
		debuglog("TESTING!");
	$startindex=$endindex+1;
	}	
	debuglog("Everything seems valid, returning all possible targets".Data::Dumper::Dumper(\@newtargets, \@alltargets). Data::Dumper::Dumper($variables));
	return \@newtargets, \@alltargets, $variables;
	
	
	
}

sub findtargets_revised {
	my $weare=shift;
	my $target=shift;
	my $targetting = shift;
	my $lane=[];
	my $olane=[];
	my $totalvalidtargets= 0;
	my $raw = [];
	my $players=[];
	my $variables;
#	debuglog(Data::Dumper::Dumper($players));
	if ($alltargets->{$target}{targettype} eq "Creature"){
		 
		($lane, $olane, $totalvalidtargets, $variables) = findtargets ($weare, $target, $targetting);
					
	}elsif ($alltargets->{$target}{targettype} eq "Creatureorplayer" ){
		($lane, $olane, $totalvalidtargets, $variables) = findtargets ($weare, $target, $targetting);
		$players = [1, 2];
		$totalvalidtargets+=2;
		debuglog(Data::Dumper::Dumper($players));
	}elsif ($alltargets->{$target}{targettype} eq "lane" ){
		
		($lane, $olane, $totalvalidtargets) = findtargetlane ($weare, $target, $targetting);
				
		
		}elsif ($alltargets->{$target}{targettype} eq "controller" or $alltargets->{$target}{targettype} eq "none")  {
				$lane= [];
				$olane= [];
		}elsif ($alltargets->{$target}{targettype} eq "cardinhand"){
			
			foreach my $card (@{$gamedata->{players}{$weare}{hand}} ){
				if (checktarget($target, $card, $targetting, $weare)){
					push (@{$raw}, $card);
					$totalvalidtargets+=1;
				}
			}
		}
		
	#debuglog(Data::Dumper::Dumper($lane, $olane, $raw, $totalvalidtargets));
# 	debuglog(Data::Dumper::Dumper($players));
	return $lane, $olane, $raw, $totalvalidtargets, $variables, $players;
}
sub findtargetlane {
	my $weare = shift;
	my $target = shift;
	my $targetting = shift;
	my $variables = shift;
	
	my $opp = 1;
	if ($weare == 1) {
		$opp=2;
	}
	my $totalvalidtargets=0;
	my @lane;
	my @olane;
	for my $lane (1..5) {
		
		debuglog("Checking target $target for lane $lane");
		if (checktargetlane($weare, $lane, $target, $targetting, $variables) ){
			debuglog("This is a legal target!");
			push(@lane, $lane);
			$totalvalidtargets += 1;
		}
		if (checktargetlane($opp, $lane, $target, $targetting, $variables) ){
			push(@olane, $lane);
			$totalvalidtargets += 1;					
		}
	
	}
	
	return \@lane, \@olane, $totalvalidtargets;
	
}
sub findtargets {
	my $weare = shift;
	my $target = shift;
	my $targetting = shift;
	my $variables={};
	my $opp = 1;
	if ($weare == 1) {
		$opp=2;
	}
	my $totalvalidtargets=0;
	my @lane;
	my @olane;
	my $emptylane = 0;
	if ($alltargets->{$target}{targettype} eq "lane"){
        $emptylane=1;
	}
		for my $lane (1..5) {
                #debuglog("lane is $lane");
				if ($gamedata->{lane}{$weare}{$lane} == 0 ){
                    if ($emptylane) {
                        #debuglog("Checking target $target for empty lanes");
                        if (checktargetlane($weare, $lane, $target, $targetting) ){
                            debuglog("This is a legal target!");
                            push(@lane, "l$lane");
                            $totalvalidtargets += 1;
                        }
                    }
                    
					next;
				}
				
				if ($emptylane){
                    next;
				}
				if (my $tmp = checktarget($target, $gamedata->{lane}{$weare}{$lane}, $targetting, $weare ) ){
                    foreach my $key (keys %{$tmp}){
						$variables->{$key}=$tmp->{$key};
					}
					push (@lane, $lane);
					$totalvalidtargets +=1;
				}
			}
			#debuglog("going to opp lanes");
			for my $lane (1..5) {
				if ($gamedata->{lane}{$opp}{$lane} == 0 ){
                    if ($emptylane){
                        
                        if (checktargetlane($opp, $lane, $target, $targetting) ){
                            push(@olane, "ol$lane");
                            $totalvalidtargets += 1;
                        }
                    }
					next;
				}
				if ($emptylane){
                    next;
				}
				if (my $tmp=checktarget($target , $gamedata->{lane}{$opp}{$lane}, $targetting, $weare ) ){
                    foreach my $key (keys %{$tmp}){
						$variables->{$key}=$tmp->{$key};
					}
					push (@olane, $lane);
					$totalvalidtargets +=1;
				}
			}
	 return \@lane, \@olane, $totalvalidtargets, $variables;
}


sub checktargetwrapper {
    my $target = shift;
	my $object=shift;
	my $weare = shift;
	my $lane = shift;
	my $targetting = shift;
	
	if  ($alltargets->{$target}{targettype} eq "lane"){
        
        return checktargetlane($weare, $lane, $target, $targetting);
        
	}else {
		#debuglog(caller);
        return checktarget($target, $object, $targetting, $weare);
	}
	
}

sub checktargetlane  {
    my $weare = shift;
    my $lane = shift;
    my $target = shift;
    my $targetting = shift;
    my $variables= (shift or {});
    $variables->{friendly} = 0;
    $variables->{distance} = 0;
    my $object={};
    if ($weare == $gamedata->{objects}{$targetting}{owner}){
        $variables->{friendly} = 1;
    }
    
    if ($gamedata->{lane}{$weare}{$lane} ) {
		$variables->{empty}=0;
		$object = $gamedata->{objects}{$gamedata->{lane}{$weare}{$lane} }
    }else {
		$variables->{empty}=1;
    }
    
    if ($targetting) {
        debuglog("our distance is: abs($gamedata->{objects}{$targetting}{lane} - $lane)");
        $variables->{distance} = abs($gamedata->{objects}{$targetting}{lane} - $lane);
        debuglog($variables->{distance});
    }else {
        debuglog("not targetting");
    }
#     debuglog("variables in check target lane: ".Data::Dumper::Dumper($variables));
#     debuglog($variables->{distance});

    if (!triggercompare($gamedata->{objects}{$targetting}, $object, $alltargets->{$target}{target1var}, $alltargets->{$target}{target1compare},$alltargets->{$target}{target1target}, $variables)){
		debuglog("We failed, returning!");
		return 0;
	}
# 	debuglog("variables in check target lane2: ".Data::Dumper::Dumper($variables));
    
    if (!triggercompare($gamedata->{objects}{$targetting}, $object, $alltargets->{$target}{target2var}, $alltargets->{$target}{target2compare},$alltargets->{$target}{target2target}, $variables)){
		return 0;
	}
# 	debuglog("variables in check target lane3: ".Data::Dumper::Dumper($variables));
    
    if (!triggercompare($gamedata->{objects}{$targetting}, $object, $alltargets->{$target}{target3var}, $alltargets->{$target}{target3compare},$alltargets->{$target}{target3target}, $variables)){
		return 0;
	}
    return $variables;
    
}


#Takes 
#$target  (string alltargets index)
#$object  (Object in the lane if any)
#$weare  

sub checktarget {
	my $target = shift;
	my $object=shift;
	my $targetting=shift;
	my $weare = shift;
	my %variables;
	
	if (!$target) {
		return \%variables;
	}
# 	debuglog(caller);
	if (!triggercompare( $gamedata->{objects}{$targetting}, $gamedata->{objects}{$object},$alltargets->{$target}{target1var}, $alltargets->{$target}{target1compare},$alltargets->{$target}{target1target})){
		return 0;
	}
	if (!triggercompare( $gamedata->{objects}{$targetting}, $gamedata->{objects}{$object},$alltargets->{$target}{target2var}, $alltargets->{$target}{target2compare},$alltargets->{$target}{target2target})){
		return 0;
	}
	if (!triggercompare( $gamedata->{objects}{$targetting}, $gamedata->{objects}{$object},$alltargets->{$target}{target3var}, $alltargets->{$target}{target3compare},$alltargets->{$target}{target3target})){
		return 0;
	}
	if ($alltargets->{$target}{variablename}){ 
		debuglog("we're looking for a variable!");
		my @results = split(/\./, $alltargets->{$target}{variablevalue});
		my $var1;
		if ($results[0] eq "self"){
			if ($results[1] eq "controller"){
				$var1=$gamedata->{players}{ $gamedata->{objects}{$targetting}{owner} }{$results[2] };
			}elsif ($results[1] eq "cardsinhand"){
				my $number=0;
				foreach my $card ( @{$gamedata->{players}{$gamedata->{objects}{$targetting}{owner}}{hand}}){
						$number ++;
				}
				$var1=$number;
			}elsif ($results[1] eq "lanesfilled"){
                my $total=0;
                for my $lane (1..5) {
                    if ($gamedata->{lane}{ $gamedata->{objects}{$targetting}{owner} }{$lane} > 0){
                        $total += 1;
                    }
                }
                $var1=$total;
                debuglog("checking lanesfilled, value = $total");
            }elsif ($results[1] eq "factioninhand"){
				my $number=0;
				foreach my $card ( @{$gamedata->{players}{$gamedata->{objects}{$targetting}{owner}}{hand}}){
					if ($gamedata->{objects}{$card}{Faction} eq $results[2]){
						$number ++;
					}
				}
				$var1=$number;
			}elsif ($results[1] eq "keyword"){
				$var1=checkkeyword($results[2], $targetting)
			}else {
				if (!defined $gamedata->{objects}{$targetting}{$results[1]}){
					debuglog("Error, not defined in self! ".Data::Dumper::Dumper($gamedata->{objects}{$object} ));
				
					return 0;
				}
				$var1=$gamedata->{objects}{$targetting}{$results[1]};
			}
		}
        if ($results[0] eq "target"){
			if ($results[1] eq "controller"){
				$var1=$gamedata->{players}{ $gamedata->{objects}{$object}{owner} }{$results[2] };
			}elsif ($results[1] eq "cardsinhand"){
				my $number=0;
				foreach my $card ( @{$gamedata->{players}{$gamedata->{objects}{$object}{owner}}{hand}}){
						$number ++;
				}
				$var1=$number;
			}elsif ($results[1] eq "factioninhand"){
				my $number=0;
				foreach my $card ( @{$gamedata->{players}{$gamedata->{objects}{$object}{owner}}{hand}}){
					if ($gamedata->{objects}{$card}{Faction} eq $results[2]){
						$number ++;
					}
				}
				$var1=$number;
			}elsif ($results[1] eq "keyword"){
				$var1=checkkeyword($results[2], $object)
			}else {
				if (!defined $gamedata->{objects}{$object}{$results[1]}){
					debuglog("Error, not defined in target! ".Data::Dumper::Dumper($gamedata->{objects}{$object} ));
				
					return 0;
				}
				$var1=$gamedata->{objects}{$object}{$results[1]};
			}
		}
		if ($results[0] eq "core"){
			$var1=$gamedata->{$results[1]};
		}
		$variables{ $alltargets->{$target}{variablename} } = $var1;
        debuglog("Found variable! $var1");
	}
	return \%variables;
	
	
	
	 
}

sub checkplays {
	kfgameshared::checkstatebased($game);
    my $canplay="";
	my @canplay;
	my $weare = $gamedata->{turn};
	outer: foreach my $lane (1..5){
		if ($gamedata->{lane}{$weare}{$lane}>0){
			my $card = $gamedata->{lane}{$weare}{$lane};
			my $card2 = $card;
			if (ref $gamedata->{objects}{$card}{activated} ne "ARRAY"){
                next;
			}
			my $numberofactivated = scalar  @{$gamedata->{objects}{$card}{activated}};
			if (checkkeyword("Move", $card) > 0){
                $numberofactivated += 1;
			}
			$numberofactivated-=1;
			if ($numberofactivated< 0 ){
                next;
			}
			debuglog("number of activated abilities: $card, $numberofactivated");
			foreach my $index (0..$numberofactivated){
                debuglog("index: $index of $numberofactivated");
                my $ability = $gamedata->{objects}{ $card }{activated}[$index];
                if (!$ability and checkkeyword("Move", $card) > 0 ) {
                    my $warp = checkkeyword("Move", $card);
                        if ($warp == 1){
                            $ability = 1
                        }
                        if ($warp == 2){
                            $ability = 2
                        }
                        if ($warp == 3){
                            $ability = 3
                        }
                        if ($warp >= 4){
                            $ability = 4                        
                        }
                }
                if ( $ability  ){
                    debuglog("We found an activated ability to try to activate: $ability - $index");
                    debuglog("$allactivated->{ $ability }{targetindex}");
                    if ($gamedata->{objects}{$card}{ss}>0 and checkkeyword("Aggressive", $card) <=0 ){
                        debuglog("We're SS");
                        next outer;
                    }
                    if (defined $gamedata->{objects}{$card}{activatedthisturn}{$index} ){
                        next;
                    }
				
                    my $targets= [];
                    foreach my $target ( split(",", $allactivated->{ $ability }{targetindex} ) ){
                        debuglog("trying to find targets from $target target");
					
                        my $lane;
                        my $olane;
                        my $raw;
                        my $totalvalidtargets;
                        my $players;
                        my $variables;
                        if (!$target){
                            next;
                        }
                        ($lane, $olane, $raw, $totalvalidtargets, $variables, $players) = findtargets_revised($gamedata->{turn}, $target, $card);
						if ($totalvalidtargets < $alltargets->{$target}{mintargets}){
							debuglog("Not enough targets! ".$totalvalidtargets);
							next outer;
						}
						my $name = $allactivated->{ $ability }{name};
						if (!$name){
                            $name = $gamedata->{objects}{$card}{Name};
                            
						}
						push @{$targets},  {
							'text' => $alltargets->{$target}{text},
							'raw' => $raw,
							l => $lane,
							o => $olane,
							players => $players,
							mintargets => $alltargets->{$target}{mintargets},
							maxtargets => $alltargets->{$target}{maxtargets},
							'index' => $index,
							name => $name,
						};
				
                
                        
					}
				
                $card2="$card:".to_json($targets);		
				debuglog("card2 is $card2");
				push (@canplay, $card2);
                }
            }
        }
    }
    outer: foreach my $card (@{$gamedata->{players}{$gamedata->{turn} }{hand} }){
       
		if (checkkeyword("Free", $card) > 0){
			debuglog("this is a free card! $card");
		}else {
			if ($gamedata->{objects}{$card}{cost} > $gamedata->{playsremaining})  {
                #we don't have enough actions!
                
				next;
			}
		}
        my $card2=$card;
        if ($gamedata->{objects}{$card}{CardType} eq "Creature"){
        
            my $targets= [{
                'text' => "Choose lane for Creature",
                    l => [1, 2, 3, 4, 5]
            }];
                
            $card2="$card:".to_json($targets);
        }elsif ($gamedata->{objects}{$card}{CardType} eq "Spell"){
        	
            my $targets= [];
            my $lane;
            my $olane;
            my $raw;
            my $players;
            my $variables;
            my $totalvalidtargets;
            if (!$gamedata->{objects}{$card}{targets}){
                next outer;
                
            }
            foreach my $target (split (",",$gamedata->{objects}{$card}{targets} )){
                if (!$target){
                    next;
                }
                if (! defined $alltargets->{$target}) {
					debuglog("ERROR $target isn't defined!");
                }
                ($lane, $olane, $raw, $totalvalidtargets, $variables, $players) = findtargets_revised($gamedata->{turn}, $target, $card);
				if ($totalvalidtargets < $alltargets->{$target}{mintargets}){
					debuglog("Not enough targets! ".$totalvalidtargets);
					next outer;
				}
				if ($alltargets->{$target}{Selector} eq "All"){
                    push @{$targets},  {
						'text' => $alltargets->{$target}{text},
						'raw' => [],
						l => [],
						o => [],
						players => [],
						mintargets => 0,
						maxtargets => 0
						};
				
				}else {
                    push @{$targets},  {
						'text' => $alltargets->{$target}{text},
						'raw' => $raw,
						l => $lane,
						o => $olane,
						players => $players,
						mintargets => $alltargets->{$target}{mintargets},
						maxtargets => $alltargets->{$target}{maxtargets}
						};
				
                    }
                }
            debuglog("We found ".Data::Dumper::Dumper($targets)." Targets");
            $card2="$card:".to_json($targets);
            }
        
			push (@canplay, $card2);
        }
        $canplay=join(";", @canplay);
        if (length ($canplay) == 0){
            $canplay="[]";
        }
        $dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `handplayable`) VALUES(?, ?)", undef, ($gamedata->{players}{$gamedata->{turn}}{playerid}, $canplay ));
        $gamedata->{hidden}{$gamedata->{turn}}{handplayable}=$canplay;
}

sub checkarmor {
    my $object=shift;
    my $armor = checkkeyword("Armor", $object);
    if (defined $gamedata->{objects}{$object}{armorthisturn}){
        $armor -= $gamedata->{objects}{$object}{armorthisturn};
    }
    if ($armor < 0 ){
        $armor =0;
    }
    return $armor;
}

sub checktrain {
	my $canplay="";
	my @canplay;

    outer: foreach my $card (@{$gamedata->{players}{$gamedata->{turn} }{hand} }){
        	
		if ($gamedata->{objects}{$card}{CardType} ne "Creature"){
			next;
		}
		if ($gamedata->{objects}{$card}{cost} > $gamedata->{playsremaining}){
                #we don't have enough gold!
                
			next;
		}
        my $card2=$card;
        my $targets= [{
            'text' => "Choose lane for Creature",
                l => [1, 2, 3, 4, 5]
        }];
                
        $card2="$card:".to_json($targets);
        push (@canplay, $card2);
        
        
        
        $canplay=join(";", @canplay);
        if (length ($canplay) == 0){
            $canplay="[]";
        }
        $dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `handplayable`) VALUES(?, ?)", undef, ($player->{userId}, $canplay ));
	$gamedata->{hidden}{$gamedata->{turn}}{handplayable}=$canplay;
}
}

#check if this Creature can battle, id is gameobject id. return 1 can battle, return 0 can not attack but will still defend itself
sub checkcanbattle {
	my $id=shift;
	if ($id <=0){
		return 0;
	}
	if ($gamedata->{objects}{$id}{ss}>0 and checkkeyword("Aggressive", $id)<=0 ){
		return 0;
	}
	if (checkkeyword("Defender", $id) > 0){
		return 0;
	}
	
	if ($gamedata->{turnphase} >= $gamedata->{objects}{$id}{battlesthisturn}){
        return 0;
	}
	return 1;
}


sub loadtargets {
	my $triggers = $dbh->selectall_hashref("SELECT * from `KF_cards`.`targets`", "targetid" );
	return $triggers;
}
sub loadeffects {
	my $triggers = $dbh->selectall_hashref("SELECT * from `KF_cards`.`effects`", "effectid" );
	return $triggers;
}
sub loadtriggers {
	my $triggers = $dbh->selectall_hashref("SELECT * from `KF_cards`.`triggers`", "triggerid" );
	return $triggers;
}
sub loadactivated {
	my $triggers = $dbh->selectall_hashref("SELECT * from `KF_cards`.`Activated`", "ActivateId" );
	return $triggers;
}
sub loadstatic {
	my $triggers = $dbh->selectall_hashref("SELECT * from `KF_cards`.`static`", "id" );
	return $triggers;
}
sub loadcards{
	my $cardnames=$dbh->selectall_hashref("SELECT * from `KF_cards`.`carddata`", "CardId" );
	my $cardids=$dbh->selectall_hashref("SELECT * from `KF_cards`.`carddata`", "Name" );
	my %allcards;
	foreach my $cardid (keys %$cardnames) {
		$allcards{$cardid}=$cardnames->{$cardid};
	}
	foreach my $cardname (keys %$cardids) {
		$allcards{$cardname}=$cardids->{$cardname};
		$allcards{lc($cardname)}=$cardids->{$cardname};

	}
	return \%allcards;
}



sub end {
    my $result=shift;
    if (!$result->{status}){
        $result->{status}= "Success";
    }
    my $response = to_json($result);
    print "Content-Type: Text/JSON\n\n";
    print "$response";

    exit;

}



sub logmessage {
	my $message = shift;
# 	debuglog("turn is: $gamedata->{turn}");
	$message = substr($message, 0, 250);
	$dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `logmessage`, `turn`) VALUES(0, ?, ?)", undef, ($message, $gamedata->{turn}) );

}






1;
