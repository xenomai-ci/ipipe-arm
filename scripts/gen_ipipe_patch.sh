#! /bin/sh

me=`basename $0`
usage='usage: $me [--split] [--help] [reference]'
split=no

while test $# -gt 0; do
    case "$1" in
    --split)
	split=yes
	;;
    --help)
	echo "$usage"
	exit 0
	;;
    *)
	if [ -n "$reference" ]; then
	    echo "$me: unknown flag: $1" >&2
	    echo "$usage" >&2
	    exit 1
	fi
	reference="$1"
	;;
    esac
    shift
done

VERSION=`sed 's/^VERSION = \(.*\)/\1/;t;d' Makefile`
PATCHLEVEL=`sed 's/^PATCHLEVEL = \(.*\)/\1/;t;d' Makefile`
SUBLEVEL=`sed 's/^SUBLEVEL = \(.*\)/\1/;t;d' Makefile`
EXTRAVERSION=`sed 's/^EXTRAVERSION = \(.*\)/\1/;t;d' Makefile`

if [ -z "$SUBLEVEL" -o "$SUBLEVEL" = "0" ]; then
    kvers="$VERSION.$PATCHLEVEL"
elif [ -z "$EXTRAVERSION" ]; then
    kvers="$VERSION.$PATCHLEVEL.$SUBLEVEL"
else
    kvers="$VERSION.$PATCHLEVEL.$SUBLEVEL.$EXTRAVERSION"
fi

if [ -z "$reference" ]; then
    reference="v$kvers"
fi

echo reference: $reference, kernel version: $kvers

git diff "$reference" | awk -v kvers="$kvers" -v splitmode="$split" \
'function set_current_arch(a)
{
    if (!outfiles[a]) {
	mt = "mktemp /tmp/XXXXXX"
	mt | getline outfiles[a]
	close(mt)
    }
    current_arch=a
    current_file=outfiles[a]
}

BEGIN {
    driver_arch["cpuidle/Kconfig"]="noarch"
    driver_arch["cpuidle/cpuidle.c"]="noarch"
    driver_arch["tty/serial/8250/8250_core.c"]="noarch"
    driver_arch["iommu/irq_remapping.c"]="noarch"
}

match($0, /^diff --git a\/arch\/([^ \t\/]*)/) {
    split(substr($0, RSTART, RLENGTH), arch, /\//)
    a=arch[3]

    is_multiarch=0
    set_current_arch(a)
    print $0 >> current_file
    next
}

match($0, /^diff --git a\/drivers\/base/) {
    set_current_arch("noarch")
    is_multiarch=0
    print $0 >> current_file
    next
}

match($0, /^diff --git a\/drivers\/([^ \t]*)/) {
    file=substr($0, RSTART, RLENGTH)
    sub(/^diff --git a\/drivers\//, "", file)
    f=file

    if (!driver_arch[f]) {
	 print "Error unknown architecture for driver "f
	 unknown_file_error=1
    } else {
        a = driver_arch[f]
        if(index(a, " ")) {
            is_multiarch = 1
            split(a, multiarch, " ")
            for(a in multiarch) {
                set_current_arch(multiarch[a])
                print $0 >> current_file
            }
        } else {
            is_multiarch = 0
            set_current_arch(a)
            print $0 >> current_file
        }
        next
    }
}

/^diff --git a\/scripts\/gen_ipipe_patch.sh/ {
    is_multiarch=0
    if (splitmode == "no") {
	current_file="/dev/null"
	current_arch="nullarch"
	next
    }
}

/^diff --git/ {
    set_current_arch("noarch")
    is_multiarch=0
    print $0 >> current_file
    next
}

match ($0, /#define [I]PIPE_CORE_RELEASE[ \t]*([^ \t]*)/) {
    split(substr($0, RSTART, RLENGTH), vers, /[ \t]/)
    version[current_arch]=vers[3]
}

{
    if(is_multiarch) {
        for(a in multiarch) {
            set_current_arch(multiarch[a])
            print $0 >> current_file
        }
    } else {
        print $0 >> current_file
    }
}

END {
    close(outfiles["noarch"])
    for (a in outfiles) {
	if (unknown_file_error) {
	    if (a != "noarch")
		system("rm "outfiles[a])
	} else if (a != "noarch") {
	    dest="ipipe-core-"kvers"-"a"-"version[a]".patch"
	    close(outfiles[a])
	    system("mv "outfiles[a]" "dest)
	    if (splitmode == "no")
		system("cat "outfiles["noarch"]" >> "dest)
	    print dest
	} else if (splitmode == "yes") {
	    dest="ipipe-core-"kvers"-"a".patch"
	    system("cat "outfiles["noarch"]" > "dest)
	    print dest
	}
    }

    system("rm "outfiles["noarch"])
}
'
