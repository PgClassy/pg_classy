#! /usr/bin/env bash

set -o errexit -o errtrace -o pipefail
trap 'echo "Error on line ${LINENO}" >&2' ERR

BASEDIR=`dirname $0`
META=$BASEDIR/META.json
JSON_SH=$BASEDIR/pgxntool/JSON.sh

error () {
  echo $@ >&2
}
trap 'error "Error on line ${LINENO}"' ERR

die () {
  local retval=$1
  shift
  error $@
  exit $retval
}

#function to get value of specified key
#returns empty string if not found
#warning - does not validate key format (supplied as parameter) in any way, simply returns empty string for malformed queries too
#usage: VAR=$(getkey foo.bar) #get value of "bar" contained within "foo"
#       VAR=$(getkey foo[4].bar) #get value of "bar" contained in the array "foo" on position 4
#       VAR=$(getkey [4].foo) #get value of "foo" contained in the root unnamed array on position 4
function _getkey {
    #reformat key string (parameter) to what JSON.sh uses
    KEYSTRING=$(sed -e 's/\[/\"\,/g' -e 's/^\"\,/\[/g' -e 's/\]\./\,\"/g' -e 's/\./\"\,\"/g' -e '/^\[/! s/^/\[\"/g' -e '/\]$/! s/$/\"\]/g' <<< "$@")
    #extract the key value
    FOUT=$(grep -F "$KEYSTRING" <<< "$JSON_PARSED")
    FOUT="${FOUT#*$'\t'}"
    FOUT="${FOUT#*\"}"
    FOUT="${FOUT%\"*}"
    echo "$FOUT"
}
function getkeys {
    KEYSTRING=$(sed -e 's/\[/\"\,/g' -e 's/^\"\,/\[/g' -e 's/\]\./\,\"/g' -e 's/\./\"\,\"/g' -e '/^\[/! s/^/\[\"/g' -e '/\",\"$/! s/$/\",\"/g' <<< "$@")
    #extract the key value
    FOUT=$(grep -F "$KEYSTRING" <<< "$JSON_PARSED")
    FOUT="${FOUT%$'\t'*}"
    echo "$FOUT"
}

#function returning length of array
#returns zero if key in parameter does not exist or is not an array
#usage: VAR=$(getarrlen foo.bar) #get length of array "bar" contained within "foo"
#       VAR=$(getarrlen) #get length of the root unnamed array
#       VAR=$(getarrlen [2].foo.bar) #get length of array "bar" contained within "foo", which is stored in the root unnamed array on position 2
function getarrlen {
    #reformat key string (parameter) to what JSON.sh uses
    KEYSTRING=$(gsed -e '/^\[/! s/\[/\"\,/g' -e 's/\]\./\,\"/g' -e 's/\./\"\,\"/g' -e '/^$/! {/^\[/! s/^/\[\"/g}' -e '/^$/! s/$/\"\,/g' -e 's/\[/\\\[/g' -e 's/\]/\\\]/g' -e 's/\,/\\\,/g' -e '/^$/ s/^/\\\[/g' <<< "$@")
    #extract the key array length - get last index
    LEN=$(grep -o "${KEYSTRING}[0-9]*" <<< "$JSON_PARSED" | tail -n -1 | grep -o "[0-9]*$")
    #increment to get length, if empty => zero
    if [ -n "$LEN" ]; then
        LEN=$(($LEN+1))
    else
        LEN="0"
    fi
    echo "$LEN"
}

function getkey {
  out=$(_getkey "$@")
  [ -n "$out" ] || die 2 "key '$@' not found in $META"
  echo $out
}

JSON_PARSED=$(cat $META | $JSON_SH -l)

# Handle meta-spec specially
spec_version=`getkey meta-spec.version`
[ "$spec_version" == "1.0.0" ] || die 2 "Unknown meta-spec/version: $PGXN_meta-spec_version"

# vi: expandtab ts=2 sw=2
