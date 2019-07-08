#!/bin/bash

# param 1: the large tsv (gzipped)
# param 2: the caller id
# param 3: the truth set caller id
# param 4: which type of variant to create plots for (ex: DEL, INS, SNP, .); separate each variant by commas if you'd like to micro average over multiple of them
# param 5: the output file or '-' if stdout
# param 6 (optional): if you'd like to exclude some variants from analysis, specify the caller id, a tilde "~", the name of the column to use for filtering, a comparison operator (>, <, ==), and the value to compare against (ex: 'gatk-indel~DP>20'); you can specify multiple filtering expressions by separating them with commas but the order in which they are given must match that of the tsv

# make sure that the large tsv has columns in the order caller~REF, caller~ALT, truth~REF, truth~ALT


script_dir="$(dirname "$BASH_SOURCE")";

function binarize() {
	# use awk to convert each column to binary 1s or 0s based on what type of
	# variant we want to create plots for

	# if the user didn't specify a type of variant, don't do any filtering
	if [ -z "$1" ]; then
		cat
	# if the user specified '.' as the variant, label '.' as 0 and everything else as 1
	elif [ "$1" == '.' ]; then
		awk '!/\./ {print 1} /\./ {print 0}'
	# if the user specified a comma-separated list of variant types, aggregate the resuts of binarizing all of them
	elif [[ $1 == *","* ]]; then
		local col="$(cat)"
		# create an array of variant types called "$variants"
		IFS=',' read -ra variants <<< "$1"
		# call binarize on the same input with each variant type
		for i in "${!variants[@]}"; do
			variants[$i]="<(echo \"\$col\" | binarize "${variants[$i]}")"
		done
		eval "paste -d '\n' ${variants[@]}"
	# if the user specified 'INS', 'DEL', or 'SNP' as the variant, label it as 1 and everything else as 0
	else
		awk '/'"$1"'/ {print 1} !/'"$1"'/ {print 0}'
	fi
}

function filter_cols() { cat; }
# are there columns to filter on?
if [ ! -z "$6" ]; then
	# retrieve an array of the columns to filter on, sorted according to their order in the tsv
	filter_col="$(tr , '\n' <<< "$6" | sed -r 's/(>|<|==).*$//')"
	# prepare a pipe delimited list of the columns to filter on
	filter_cols="$(paste -s -d'|' <<< "$filter_col")"
	# prepare a function for filtering the rows
	function filter_cols() {
		awk -F $"\t" -v 'OFS=\t' "$(gawk -v'RS=,' -v'ORS= && ' '{split($0,a,"(>|<|==)",seps); print "$" ++i+2 seps[length(seps)] a[length(a)] }' <<< "$1" | head -n1)" | cut -f -2;
	}
fi

# use paste to create a two column table of true variants (col1) and their predictions (col2)
# if needed, we binarize the columns according to what the user has defined as the positive label
paste <(
	zcat "$1" | "$script_dir"/get_cols.bash "^$3~(REF|ALT)$" | tail -n+2 | \
	"$script_dir"/classify.awk | binarize "$4"
) <(
	zcat "$1" | "$script_dir"/get_cols.bash "^$2~(REF|ALT)$" | tail -n+2 | \
	"$script_dir"/classify.awk | binarize "$4"
) | {
	if [ -z "$6" ]; then
		cat
	else
		paste - <(
			zcat "$1" | "$script_dir"/get_cols.bash '^('"$filter_cols"')$' | tail -n+2 | \
			binarize "$(sed 's/[^,]//g' <<< "$4"),"
		)
	fi
} | filter_cols "$6" | \
python "$script_dir"/metrics.py -o "$5";
