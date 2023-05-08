#!/usr/bin/perl -w
my $data= <<eof;
common,Building,Boiling Volcano,,Ritual: Deal 1 damage to all creatures and players,3,F,
common,Spell,Flame Wave,,Deal 2 damage to all players and creatures,2,FF,
common,Spell,Incinerate,,Deal 4 damage to target creature and yourself,1,F,
common,Spell,Equal Burn,,Deal 3 damage to each player,1,F,
common,Unit,Flame Rider,Human,When ~ is played it deals 3 damage to the opposing creature or player if no creature,3,FF,3/1
common,Unit,Keeper of Balance,Salamander,When ~ is played deal 2 damage to each player,2,F,2/1
common,Unit,Rage,Elemental,Unblockable,3,F,3/2
common,Unit,Aggressive Scout,Human,When you play ~ you may move to attack on your next  turn,1,F,1/1
common,Unit,Sprite Summoner,Slith,When ~ is played create a 2/1 sprite in a random lane, it has 'this creature dies when it deals damage',3,F,2/1
rare,Buidling,Fire Circle,,Ritual: Create a 2/1 sprite with 'this creature dies when it deals damage' in a random lane,2,F,
rare,Spell,Controlled Fury,,Enemy creatures lose and can't gain evade,2,F,
rare,Spell,Purifying Flame,,Enemy creatures lose and can't gain Miasma,2,F,
rare,Spell,Uncontrolled Rage,,Target creature attacks it's controller,3,FF,
rare,Unit,Fire Elemental,Elemental,Relentless,6,F,8/2
rare,Unit,Contained Flame,Elemental,When this dies deal 2 damage to all other creatures,3,F,4/1
rare,Unit,Enlightened Flame,Human,'Ritual: Sacrifice this, draw 3 cards and gain 2 life',3,F,2/2
rare,Unit,FlameWalker,Human,Resistance 3,3,F,3/3
rare,Unit,Returned Flameseeker,Gnome,When you explore this card deal 2 damage to a creature,3,F,2/2
Legend,Building,Flame Projector,,Ritual: Deal 3 damage to each opponent,5,F,
Legend,Spell,Fireball,,Deal 10 damage to creature and 5 damage to a player,5,F,
Legend,Unit,Flame Slinger,Human,Ritual: Deal 2 damage to opposing creature,4,F,5/3
Legend,Unit,Sprite Master,Slith,When you play ~ create a 2/1 sprite in each of your empty lanes, they have 'this creature dies when it deals damage',6,F,5/4
Legend,Unit,Growing Flame,Elemental,If the creature opposite of this dies\, this gains +2/+3,3,F ,2/3
Legend,Unit,Sprite Eater,Elemental,Whenever a sprite you control dies this gains +1/+1,4,F,2/2
Legend,Unit,Enlightened Focus,Human,Ritual: Draw a spell,4,F,3/4
eof

my @rows = split("\n", $data);
print "Content-type: Text/html\r\n\r\n";
foreach my $row (@rows) {
	my @column = split(/(?<!\\),/, $row);
	my $faction;
	if ($column[6] =~ /A/){
		$faction="Air";
	}
	$column[4]=~s/\"/\\"/g;
	print "INSERT INTO `carddata`(`Name`,`CardType`,`subtype`, `text`, `AttackType`, `Cost`, `threshold`, `Faction`, `rarity`) VALUES( \"$column[2]\", \"$column[1]\", \"$column[3]\", \"$column[4]\", \"Physical\",\"$column[5]\", \"$column[6]\", \"$faction\", \"$column[0]\");<BR>";
	
}
