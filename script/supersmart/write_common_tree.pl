#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use Bio::Phylo::IO 'unparse';
use Bio::Phylo::Util::Logger ':levels';
use Bio::Phylo::PhyLoTA::Service::MarkersAndTaxaSelector;
use Bio::Phylo::PhyLoTA::Domain::MarkersAndTaxa;

=head1 NAME

write_common_tree.pl - writes polytomous taxonomy tree

=head1 SYNOPSYS

 $ write_common_tree.pl --infile=<taxa table> > <outfile>

=head1 DESCRIPTION

Given a table of reconciled taxa, writes the 'common tree' that connects these taxa
in the underlying taxonomy. The resulting tree description is written to STDOUT. By
default this is in Newick syntax, with labels on interior nodes (including all available
taxonomic levels up to the root), and with the taxon IDs as terminal labels.

=cut

# process command line arguments
my $template   = '${get_guid}';  # by default, the node label is the NCBI taxon ID
my @properties = qw(get_guid); # additional column values to use in template
my $infile     = '-'; # read from STDIN by default
my $outformat  = 'newick'; # write newick by default
my $nodelabels = 1; # write internal node labels by default
my $verbosity  = INFO; # low verbosity
GetOptions(
	'template=s'  => \$template,
	'infile=s'    => \$infile,
	'outformat=s' => \$outformat,
	'verbose+'    => \$verbosity,
	'property=s'  => \@properties,
	'nodelabels'  => $nodelabels,
);

# instantiate helper objects
my $mts = Bio::Phylo::PhyLoTA::Service::MarkersAndTaxaSelector->new;
my $mt =  Bio::Phylo::PhyLoTA::Domain::MarkersAndTaxa->new;

my $log = Bio::Phylo::Util::Logger->new(
	'-class' => [ 'main' ],
	'-level' => $verbosity
);

# parse the taxa file 
my @taxatable = $mt->parse_taxa_file($infile);

# instantiate nodes from infile
my @nodes = $mts->get_nodes_for_table( @taxatable );

# compute common tree
my $tree = $mts->get_tree_for_nodes(@nodes);
$log->debug("done computing common tree");

# create node labels
$tree->visit(sub{
	my $node = shift;
	if ( $nodelabels or $node->is_terminal ) {
		my $label;		
		my $statement = "my (" . join( ',', map ("\$$_", @properties) ). ");\n";
		for my $property ( @properties ) {
			$statement .= "\$$property = q[" . $node->$property . "];\n";
			$log->debug($statement);
		}		
		$statement .= "\$label = $template";
		$log->debug($statement);
		eval $statement;
		die $@ if $@;
		$log->debug($label);
		$node->set_name( $label );
	}
});

# write output
print unparse(
	'-format'     => $outformat,
	'-phylo'      => $tree,
	'-nodelabels' => $nodelabels,
);