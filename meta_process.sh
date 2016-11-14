#! /usr/bin/env bash

set -o errexit -o errtrace -o pipefail
trap 'echo "Error on line ${LINENO}" >&2' ERR

BASEDIR=`dirname $0`
. $BASEDIR/meta_funcs.sh

usage() {
  cat << _EOF_
Usage:

$0 [options] input_file output_file

where options are
  -d      default file to use if <input_file> does not exist you must still specify the input file
  -p      prefix for all META keys

  -h      display this message
_EOF_
}

parse_options() {
default_file=''
prefix=''
while getopts d:p:h arg "$@"
do
  case "$arg" in
    d)
      default_file="$OPTARG"
      [ -e "$default_file" ] || die 2 "default file '$default_file' does not exist"
      [ -r "$default_file" ] || die 2 "default file '$default_file' is not readable"
      ;;
    p)
      prefix=$(echo "$OPTARG" | sed -e 's/\.*$//').
      ;;
    h)
      usage
      exit 0
      ;;
    ?)
      usage
      exit 1
      ;;
  esac
done
if [ $OPTIND -gt 1 ]; then
  shift $(($OPTIND-1))
fi

if [ $# -lt 1 ]; then
  echo "ERROR: Must specify input file"
  usage
  exit 1
fi
IN=$1
shift

if [ $# -lt 1 ]; then
  echo "ERROR: Must specify output file"
  usage
  exit 1
fi
OUT=$1
shift

#psql_opts=$@
#echo "IN = '$IN', OUT = '$OUT'"
}

main() {
  parse_options "$@"

  if [ ! -e "$IN" -a -n "$default_file" ]; then
    IN="$default_file"
    # We've already verified $default_file exists and is readable
  else
    [ -e "$IN" ] || die 2 "input file '$IN' does not exist"
    [ -r "$IN" ] || die 2 "input file '$IN' is not readable"
  fi

  SEP='#'
  S='\'
  SS='\\'
  CLEAN="s${SEP}${S}${SEP}${SEP}${SS}${S}${SEP}${SEP}g"
  declare -a replacements

  searches=`egrep -o '@[A-Za-z0-9]+@' $IN | sort | uniq`

  for search in $searches; do
    key=`echo $search | tr -d @`
    value=`getkey $prefix$key` || exit $?

    echo "  replacing $search with $value"

    clean_search=`echo "$search" | sed -e "$CLEAN"` # -e "s/'/''/g"`
    clean_value=`echo "$value" | sed -e "$CLEAN"` # -e "s/'/''/g"`
    #echo "clean_search = '$clean_search', clean_value = '$clean_value'"

    replacements+=(-e "s${SEP}$clean_search${SEP}$clean_value${SEP}g")
  done

  sed "${replacements[@]}" $IN > $OUT
}

main "$@"

# vi: expandtab ts=2 sw=2
