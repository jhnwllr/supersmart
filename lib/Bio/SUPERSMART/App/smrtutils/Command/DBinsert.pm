package Bio::SUPERSMART::App::smrtutils::Command::DBinsert;

use strict;
use warnings;

use Bio::Phylo::IO qw(parse unparse);
use Bio::Phylo::Util::CONSTANT ':objecttypes';

use Bio::Phylo::PhyLoTA::Service::MarkersAndTaxaSelector;

use base 'Bio::SUPERSMART::App::SubCommand';
use Bio::SUPERSMART::App::smrtutils qw(-command);

# ABSTRACT: 

=head1 NAME

DBinsert - insert custom sequences and taxa into database

=head1 SYNOPSYS


=head1 DESCRIPTION

=cut

sub options {    
	my ($self, $opt, $args) = @_;
	my $format_default = 'fasta';
	my $prefix_default = 'SMRT';
	return (
		['alignment|a=s', "alignment file(s) to insert into database, multiple files should be separatet by commata", { arg => 'file' } ],		
		['list|l=s', "list of alignment files to insert into database", { arg => 'file' } ],		
		['prefix|p=s', "prefix for generated accessions, defaults to $prefix_default", {default => $prefix_default}],
		['desc|d=s', "description for sequence(s)", {}],
		['format|f=s', "format of input alignemnt files, default: $format_default", { default => $format_default }]
	    );	
}

sub validate {
	my ($self, $opt, $args) = @_;			
	$self->usage_error('need either alignment or list argument') if not ($opt->alignment or $opt->list);
}

sub run {
	my ($self, $opt, $args) = @_;    
	
	my $logger = $self->logger;      	
	my $mts = Bio::Phylo::PhyLoTA::Service::MarkersAndTaxaSelector->new;
	
	my @files;
	if ( my $aln_str = $opt->alignment ) {
		push @files, split(',', $aln_str);
	}
	if ( my $aln_list = $opt->list ) {
		$logger->info("going to read alignment file list $aln_list");
		open my $fh, '<', $aln_list or die $!;
		my @al = <$fh>;
		close $fh;
		chomp @al; 
		push @files, @al;
	}
	$logger->info( 'Got file names of ' . scalar(@files) . ' to proecess' );
	
	my $seq_cnt = 0;
	# retrieve matrix object(s) from file(s)
	for my $file ( @files ) {
		$logger->info ("Processing alignment file $file");
		# create matrix object from file
		my $project = parse(
			'-format'     => $opt->format,
			'-type'       => 'dna',
			'-file'       => $file,
			'-as_project' => 1,
		    );
		my ($matrix) = @{ $project->get_items(_MATRIX_) };
		
		# iterate over sequences and insert into database
		for my $seq ( @{$matrix->get_entities} ) {
			my $id;
			my $name = $seq->get_name;
			$logger->info("seq name : $name");
			if ( $name=~/^[0-9]+?/ ) {
				$id = $name;
			} 
			else {
				$logger->info("Descriptor of sequence $name does not look like taxon ID, trying to map id");
				$name =~ s/_/ /g;
				$logger->info("Trying to find $name");
				my $node = $mts->find_node({taxon_name=>$name});
				$id = $node->ti;
				$logger->info("Remapped $name to $id");
			}
			# gather fields required for 'seqs' table in phylota
			my $division = 'INV';
			my $acc_vers = 1;
			my $unaligned = $seq->get_unaligned_char;
			my $length = length($unaligned);
			my $gbrel = '000';
			my $def = $opt->desc || "";
			
			$def .= " -- entry generated by SUPERSMART " . $Bio::SUPERSMART::VERSION . " --";

			my %seqids = $mts->generate_seqids($opt->prefix);
			
			my $gi = $seqids{'gi'};
			my $acc = $seqids{'acc'};
			
			my $ti = $id;

			# set accession date to today
			my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
			my $acc_date = join("-", $year + 1900, $mon, $mday);

			$mts->insert_seq({gi=>$gi, ti=>$ti, acc=>$acc, acc_vers=>$acc_vers, length=>length($unaligned), division=>$division, acc_date=>$acc_date, gbrel=>$gbrel, def=>$def, seq=>$unaligned});
			$seq_cnt++;
			
		}
		$logger->info("DONE. Inserted $seq_cnt sequences into database");
	}
	
	

}

1;