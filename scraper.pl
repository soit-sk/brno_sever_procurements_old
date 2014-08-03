#!/usr/bin/env perl
# Copyright 2014 Michal Špaček <tupinek@gmail.com>

# Pragmas.
use strict;
use warnings;

# Modules.
use Database::DumpTruck;
use Encode qw(decode_utf8 encode_utf8);
use English;
use HTML::TreeBuilder;
use LWP::UserAgent;
use URI;

# Don't buffer.
$OUTPUT_AUTOFLUSH = 1;

# URI of service.
my $base_uri = URI->new('http://www.sever.brno.cz/verejne-zakazky.html');

# Open a database handle.
my $dt = Database::DumpTruck->new({
	'dbname' => 'data.sqlite',
	'table' => 'data',
});

# Create a user agent object.
my $ua = LWP::UserAgent->new(
	'agent' => 'Mozilla/5.0',
);

# Get base root.
print 'Page: '.$base_uri->as_string."\n";
my $root = get_root($base_uri);

# Look for items.
my $key = key();
my @table = $root->find_by_tag_name('table');
my $year = 2012;
foreach my $table (@table) {
	my @tr = $table->find_by_tag_name('tr');
	shift @tr;
	foreach my $tr (@tr) {
		my ($odbor, $nazev, $zhotovitel, $cena_bez_dph)
			= map { $_->as_text }
			$tr->find_by_tag_name('td');
		($cena_bez_dph, my $poznamka_k_cene)
			= clean_price($cena_bez_dph);
		print "- $year: ".encode_utf8($nazev)."\n";
		$key++;
		$dt->insert({
			'Klic' => $key,
			'Rok' => $year,
			'Odbor' => $odbor,
			'Nazev' => $nazev,
			'Zhotovitel' => $zhotovitel,
			'Cena_bez_DPH' => $cena_bez_dph,
			'Poznamka_k_cene' => $poznamka_k_cene,
		});
	}
	$year = 2011;	
}

# Clean price.
sub clean_price {
	my $cena_bez_dph = shift;
	remove_trailing(\$cena_bez_dph);
	my $poznamka_k_cene = '';
	if ($cena_bez_dph =~ m/^(.*?)\s*(\(.*\))$/ms) {
		$cena_bez_dph = $1;
		$poznamka_k_cene .= $2;
	}
	if ($cena_bez_dph =~ m/^(.*?)\s*(K\x{010D}\/[\w\.]+)$/ms) {
		$cena_bez_dph = $1;
		$poznamka_k_cene .= $2;
	}
	$cena_bez_dph =~ s/K\x{010D}$//ms;
	$cena_bez_dph =~ s/,-$//ms;
	$cena_bez_dph =~ s/\.-$//ms;
	$cena_bez_dph =~ s/\.//gms;
	$cena_bez_dph =~ s/\s+//gms;
	$cena_bez_dph =~ s/,00$//ms;
	$cena_bez_dph =~ s/,/\./ms;
	$poznamka_k_cene =~ s/^\(//ms;
	$poznamka_k_cene =~ s/\)$//ms;
	return ($cena_bez_dph, $poznamka_k_cene);
}

# Get root of HTML::TreeBuilder object.
sub get_root {
	my $uri = shift;
	my $get = $ua->get($uri->as_string);
	my $data;
	if ($get->is_success) {
		$data = $get->content;
	} else {
		die "Cannot GET '".$uri->as_string." page.";
	}
	my $tree = HTML::TreeBuilder->new;
	$tree->parse(decode_utf8($data));
	return $tree->elementify;
}

# Removing trailing whitespace.
sub remove_trailing {
	my $string_sr = shift;
	${$string_sr} =~ s/^\s*//ms;
	${$string_sr} =~ s/\s*$//ms;
	return;
}

# Get key.
sub key {
	my $ret_ar = eval {
		$dt->execute('SELECT MAX(Klic) FROM data');
	};
	my $key;
	if ($EVAL_ERROR || ! @{$ret_ar} || ! exists $ret_ar->[0]->{'max(klic)'}
		|| ! defined $ret_ar->[0]->{'max(klic)'}
		|| $ret_ar->[0]->{'max(klic)'} == 0) {

		$key = 0;
	} else {
		$key = $ret_ar->[0]->{'max(klic)'};
	}
	return $key;
}
