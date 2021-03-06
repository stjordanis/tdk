# Copyright (c) 2018 ActiveState Software Inc.
# Released under the BSD-3 license. See LICENSE file for details.
#
# -- Tcl Module

# @@ Meta Begin
# Package teapot::tmbackport 0.1
# Meta description Management of the TM backport for Tcl 8.4 installations
# Meta description (identified by the path of their Tcl shell)
# Meta entrysource tm.tcl
# Meta included    boot_tm.txt tm.txt
# Meta platform    tcl
# Meta require     fileutil
# Meta require     logger
# Meta require     platform::shell
# @@ Meta End

# -*- tcl -*-
# -*- tcl -*-
# Copyright (c) 2007-2009 ActiveState Software Inc
# ### ### ### ######### ######### #########
## Overview

# Management of TM backport for Tcl 8.4 installations (identified by
# the path of their Tcl shell).

# ### ### ### ######### ######### #########
## Requirements

package require fileutil
package require logger
package require platform::shell

logger::initNamespace ::teapot::tmbackport
namespace eval        ::teapot::tmbackport {}

# ### ### ### ######### ######### #########
## Implementation - shell manipulation

proc ::teapot::tmbackport::shellValid {s} {
    # Check if the given shell 's' truly is a shell
    if {[catch {InfoLibraryPath $s}]} {
	return 0
    }
    return 1
}

proc ::teapot::tmbackport::shellHasCode {s} {
    # Check if the given shell 's' has either the regular TM code, or
    # our tmbackport code.

    return [shellHasCodeAt [InfoLibraryPath $s]]
}

proc ::teapot::tmbackport::shellHasCodeAt {initlibdir} {
    # Check if the given shell 's' has either the regular TM code, or
    # our tmbackport code.

    set lines [split [fileutil::cat [file join $initlibdir init.tcl]] \n]

    # Check for regular TM code (like found in Tcl 8.5)
    set pos [lsearch -glob $lines *tcl::tm::UnknownHandler*]
    if {$pos >= 0} {return 1}

    # Check for backported TM, via its boot code.
    set pos [lsearch -glob $lines {*ACTIVETCL TM-84-BACKPORT BEGIN*}]
    return [expr {$pos < 0 ? 0 : 1}]
}

proc ::teapot::tmbackport::shellAddCode {s} {
    # Add the backported tm code to the given shell 's', if not
    # already present.

    if {[shellHasCode $s]} {
	return -code error "TM is already present"
    }

    shellAddCodeAt [InfoLibraryPath $s]
    return
}

proc ::teapot::tmbackport::shellAddCodeAt {initlibdir} {
    # Add the backported tm code to the given shell 's', unconditional. Caller
    # is responsible to check for the presence.

    # Two steps
    # -1- Extend "init.tcl" with the tmbackport boot code.
    # -2- Install the actual tmbackport package under [info library]
    #     (loaded via the base auto-loader)
    # -3- Replace "safe.tcl" with a variant able to handle tcl modules
    #     (paths, glob, ...)

    variable boot_tm_code
    variable tm_code
    variable safe_code

    # Extend existing file
    set it [file join $initlibdir init.tcl]
    fileutil::appendToFile $it "\n[Code $boot_tm_code]"

    # Create new file
    set dst [file join $initlibdir tm.tcl]
    file mkdir [file dirname $dst]
    fileutil::writeFile $dst [Code $tm_code]

    # Overwrite existing file
    set dst [file join $initlibdir safe.tcl]
    file mkdir [file dirname $dst]
    fileutil::writeFile $dst [Code $safe_code]
    return
}

# ### ### ### ######### ######### #########
## Helper commands - Shell inspection

proc ::teapot::tmbackport::InfoLibraryPath {s} {
    variable ilc
    set s [file normalize $s]
    if {![info exists ilc($s)]} {
	# DANGER/NOTE: We are using internal commands of
	# package platform::shell here (CHECK, RUN).
	platform::shell::CHECK $s
	set ilc($s) [platform::shell::RUN $s {puts [info library]}]
    }
    return $ilc($s)
}

proc ::teapot::tmbackport::Code {s} {
    return "[string map "\n\t \n" [string trimright $s]]\n"
}

namespace eval ::teapot::tmbackport {
    # Cache of shell -> info library mappings.

    # Ensure that while the package is in memory we run the expensive
    # query of each unique shell (identified by its absolute and
    # normalized path) only once.

    variable  ilc
    array set ilc {}

    variable boot_tm_code {
	# ACTIVETCL TM-84-BACKPORT BEGIN -*- tcl -*-
	# Copyright (C) 2007-2008 ActiveState Software Inc.
	# Tcl Modules (TIP #189) for Tcl 8.4

	# The added code requires a Tcl core with enhanced version handling
	# per TIP #268.

	# First make the backported commands available to the auto-loader,
	# then re-setup the unknown package handler, but only for trusted
	# interpreters. For safe interpreters the regular setup is ok and
	# therefore not touched by this code. No platform dependencies, as we
	# can inspect and use the existing setup for ours.

	set auto_index(::tcl::tm::add)            [list source [file join [info library] tm.tcl]]
	set auto_index(::tcl::tm::remove)         [list source [file join [info library] tm.tcl]]
	set auto_index(::tcl::tm::list)           [list source [file join [info library] tm.tcl]]
	set auto_index(::tcl::tm::UnknownHandler) [list source [file join [info library] tm.tcl]]
	set auto_index(::tcl::tm::roots)          [list source [file join [info library] tm.tcl]]

	# Link TM searching unconditionally into the system.
	package unknown [list ::tcl::tm::UnknownHandler [package unknown]]
	# ACTIVETCL TM-84-BACKPORT END
    }

    variable tm_code {
	# -*- tcl -*-
	#
	# Searching for Tcl Modules. Defines a procedure, declares it as the
	# primary command for finding packages, however also uses the former
	# 'package unknown' command as a fallback.
	#
	# Locates all possible packages in a directory via a less restricted
	# glob. The targeted directory is derived from the name of the
	# requested package. I.e. the TM scan will look only at directories
	# which can contain the requested package. It will register all
	# packages it found in the directory so that future requests have a
	# higher chance of being fulfilled by the ifneeded database without
	# having to come to us again.
	#
	# We do not remember where we have been and simply rescan targeted
	# directories when invoked again. The reasoning is this:
	#
	# - The only way we get back to the same directory is if someone is
	#   trying to [package require] something that wasn't there on the
	#   first scan.
	#
	#   Either
	#   1) It is there now:  If we rescan, you get it; if not you don't.
	#
	#      This covers the possibility that the application asked for a
	#      package late, and the package was actually added to the
	#      installation after the application was started. It shoukld
	#      still be able to find it.
	#
	#   2) It still is not there: Either way, you don't get it, but the
	#      rescan takes time. This is however an error case and we dont't
	#      care that much about it
	#
	#   3) It was there the first time; but for some reason a "package
	#      forget" has been run, and "package" doesn't know about it
	#      anymore.
	#
	#      This can be an indication that the application wishes to reload
	#      some functionality. And should work as well.
	#
	# Note that this also strikes a balance between doing a glob targeting
	# a single package, and thus most likely requiring multiple globs of
	# the same directory when the application is asking for many packages,
	# and trying to glob for _everything_ in all subdirectories when
	# looking for a package, which comes with a heavy startup cost.
	#
	# We scan for regular packages only if no satisfying module was found.

	namespace eval ::tcl::tm {
	    # Default paths. None yet.

	    variable paths {}

	    # The regex pattern a file name has to match to make it a Tcl Module.

	    set pkgpattern {^([_[:alpha:]][_:[:alnum:]]*)-([[:digit:]].*)[.]tm$}

	    # Export the public API

	    namespace export path
	}

	proc ::tcl::tm::path {cmd args} {
	    switch -exact -- $cmd {
		add     {return [eval [linsert $args 0 ::tcl::tm::add]]}
		remove  {return [eval [linsert $args 0 ::tcl::tm::remove]]}
		list    {return [eval [linsert $args 0 ::tcl::tm::list]]}
		default {return -code error "Bad command \"$cmd\""}
	    }
	}

	# ::tcl::tm::path implementations --
	#
	#	Public API to the module path. See specification.
	#
	# Arguments
	#	cmd -	The subcommand to execute
	#	args -	The paths to add/remove. Must not appear querying the
	#		path with 'list'.
	#
	# Results
	#	No result for subcommands 'add' and 'remove'. A list of paths
	#	for 'list'.
	#
	# Sideeffects
	#	The subcommands 'add' and 'remove' manipulate the list of
	#	paths to search for Tcl Modules. The subcommand 'list' has no
	#	sideeffects.

	proc ::tcl::tm::add {path args} {
	    # PART OF THE ::tcl::tm::path ENSEMBLE
	    #
	    # The path is added at the head to the list of module paths.
	    #
	    # The command enforces the restriction that no path may be an
	    # ancestor directory of any other path on the list. If the new
	    # path violates this restriction an error wil be raised.
	    #
	    # If the path is already present as is no error will be raised and
	    # no action will be taken.

	    variable paths

	    # We use a copy of the path as source during validation, and
	    # extend it as well. Because we not only have to detect if the new
	    # paths are bogus with respect to the existing paths, but also
	    # between themselves. Otherwise we can still add bogus paths, by
	    # specifying them in a single call. This makes the use of the new
	    # paths simpler as well, a trivial assignment of the collected
	    # paths to the official state var.

	    set newpaths $paths
	    foreach p [linsert $args 0 $path] {
		if {[lsearch -exact $newpaths $p] >= 0} {
		    # Ignore a path already on the list.
		    continue
		}

		# Search for paths which are subdirectories of the new one. If
		# there are any then the new path violates the restriction
		# about ancestors.

		set pos [lsearch -glob $newpaths ${p}/*]
		# Cannot use "in", we need the position for the message.
		if {$pos >= 0} {
		    return -code error \
			"$p is ancestor of existing module path [lindex $newpaths $pos]."
		}

		# Now look for existing paths which are ancestors of the new
		# one. This reverse question forces us to loop over the
		# existing paths, as each element is the pattern, not the new
		# path :(

		foreach ep $newpaths {
		    if {[string match ${ep}/* $p]} {
			return -code error \
			    "$p is subdirectory of existing module path $ep."
		    }
		}

		set newpaths [linsert $newpaths 0 $p]
	    }

	    # The validation of the input is complete and successful, and
	    # everything in newpaths is either an old path, or added. We can
	    # now extend the official list of paths, a simple assignment is
	    # sufficient.

	    set paths $newpaths
	    return
	}

	proc ::tcl::tm::remove {path args} {
	    # PART OF THE ::tcl::tm::path ENSEMBLE
	    #
	    # Removes the path from the list of module paths. The command is
	    # silently ignored if the path is not on the list.

	    variable paths

	    foreach p [linsert $args 0 $path] {
		set pos [lsearch -exact $paths $p]
		if {$pos >= 0} {
		    set paths [lreplace $paths $pos $pos]
		}
	    }
	}

	proc ::tcl::tm::list {} {
	    # PART OF THE ::tcl::tm::path ENSEMBLE

	    variable paths
	    return  $paths
	}

	# ::tcl::tm::UnknownHandler --
	#
	#	Unknown handler for Tcl Modules, i.e. packages in module form.
	#
	# Arguments
	#	original	- Original [package unknown] procedure.
	#	name		- Name of desired package.
	#	version		- Version of desired package. Can be the
	#			  empty string.
	#	exact		- Either -exact or ommitted.
	#
	#	Name, version, and exact are used to determine
	#	satisfaction. The original is called iff no satisfaction was
	#	achieved. The name is also used to compute the directory to
	#	target in the search.
	##
	# TIP 268: version, exact => args (multiple requirements)
	##
	# Results
	#	None.
	#
	# Sideeffects
	#	May populate the package ifneeded database with additional
	#	provide scripts.

	proc ::tcl::tm::UnknownHandler {original name args} {
	    # Import the list of paths to search for packages in module form.
	    # Import the pattern used to check package names in detail.  

	    variable paths
	    variable pkgpattern

	    # Without paths to search we can do nothing. (Except falling back
	    # to the regular search).

	    if {[llength $paths]} {
		set pkgpath [string map {:: /} $name]
		set pkgroot [file dirname $pkgpath]
		if {$pkgroot eq "."} {
		    set pkgroot ""
		}

		# We don't remember a copy of the paths while looping. Tcl
		# Modules are unable to change the list while we are searching
		# for them. This also simplifies the loop, as we cannot get
		# additional directories while iterating over the list. A
		# simple foreach is sufficient.

		set satisfied 0
		foreach path $paths {
		    if {![interp issafe] && ![file exists $path]} {
			continue
		    }
		    set currentsearchpath [file join $path $pkgroot]
		    if {![interp issafe] && ![file exists $currentsearchpath]} {
			continue
		    }
		    set strip [llength [file split $path]]

		    # We can't use glob in safe interps, so enclose the following
		    # in a catch statement, where we get the module files out
		    # of the subdirectories. In other words, Tcl Modules are
		    # not-functional in such an interpreter. This is the same
		    # as for the command "tclPkgUnknown", i.e. the search for
		    # regular packages.

		    catch {
			# We always look for _all_ possible modules in the current
			# path, to get the max result out of the glob.

			foreach file [glob -nocomplain -directory $currentsearchpath *.tm] {
			    set pkgfilename [join [lrange [file split $file] $strip end] ::]

			    if {![regexp -- $pkgpattern $pkgfilename --> pkgname pkgversion]} {
				# Ignore everything not matching our pattern
				# for package names.
				continue
			    }
			    if {[catch {package vcompare $pkgversion 0}]} {
				# Ignore everything where the version part is
				# not acceptable to "package vcompare".
				continue
			    }

			    # We have found a candidate, generate a "provide
			    # script" for it, and remember it.  Note that we
			    # are using ::list to do this; locally [list]
			    # means something else without the namespace
			    # specifier.

			    package ifneeded $pkgname $pkgversion \
				"[::list package provide $pkgname $pkgversion];[::list source $file]"

			    # We abort in this unknown handler only if we got
			    # a satisfying candidate for the requested
			    # package. Otherwise we still have to fallback to
			    # the regular package search to complete the
			    # processing.

			    if {
				$pkgname eq $name &&
				[eval [linsert $args 0 package vsatisfies $pkgversion]]
			    } then {
				set satisfied 1
				# We do not abort the loop, and keep adding
				# provide scripts for every candidate in the
				# directory, just remember to not fall back to
				# the regular search anymore.
			    }
			}
		    }
		}

		if {$satisfied} {
		    return
		}
	    }

	    # Fallback to previous command, if existing.  See comment above
	    # about ::list...

	    if {[llength $original]} {
		uplevel 1 $original [::linsert $args 0 $name]
	    }
	}

	# ::tcl::tm::Defaults --
	#
	#	Determines the default search paths.
	#
	# Arguments
	#	None
	#
	# Results
	#	None.
	#
	# Sideeffects
	#	May add paths to the list of defaults.

	proc ::tcl::tm::Defaults {} {
	    global env tcl_platform

	    foreach {major minor} [split [info tclversion] .] break
	    set exe [file normalize [info nameofexecutable]]

	    # Note that we're using [::list], not [list] because [list] means
	    # something other than [::list] in this namespace.
	    roots [::list \
		       [file dirname [info library]] \
		       [file join [file dirname [file dirname $exe]] lib] \
		      ]

	    if {$tcl_platform(platform) eq "windows"} {
		set sep ";"
	    } else {
		set sep ":"
	    }
	    for {set n $minor} {$n >= 0} {incr n -1} {
		foreach ev [::list \
				TCL${major}.${n}_TM_PATH \
				TCL${major}_${n}_TM_PATH \
			       ] {
		    if {![info exists env($ev)]} continue
		    foreach p [split $env($ev) $sep] {
			path add $p
		    }
		}
	    }
	    return
	}

	# ::tcl::tm::roots --
	#
	#	Public API to the module path. See specification.
	#
	# Arguments
	#	paths -	List of 'root' paths to derive search paths from.
	#
	# Results
	#	No result.
	#
	# Sideeffects
	#	Calls 'path add' to paths to the list of module search paths.

	proc ::tcl::tm::roots {paths} {
	    foreach {major minor} [split [info tclversion] .] break
	    foreach pa $paths {
		set p [file join $pa tcl$major]
		for {set n $minor} {$n >= 0} {incr n -1} {
		    set px [file join $p ${major}.${n}]
		    if {![interp issafe]} { set px [file normalize $px] }
		    path add $px
		}
		set px [file join $p site-tcl]
		if {![interp issafe]} { set px [file normalize $px] }
		path add $px
	    }
	    return
	}

	# Initialization. Set up the default paths, then insert the new
	# handler into the chain.

	if {![interp issafe]} { ::tcl::tm::Defaults }
    }

    variable safe_code {
	# safe.tcl --
	#
	# This file provide a safe loading/sourcing mechanism for safe interpreters.
	# It implements a virtual path mecanism to hide the real pathnames from the
	# slave. It runs in a master interpreter and sets up data structure and
	# aliases that will be invoked when used from a slave interpreter.
	# 
	# See the safe.n man page for details.
	#
	# Copyright (c) 1996-1997 Sun Microsystems, Inc.
	# Copyright (c) 2008 ActiveState Software Inc. (Backport handling Tcl Modules)
	#
	
	
	#
	# RCS: @(#) $Id: safe.tcl,v 1.9.2.3 2005/07/22 21:59:41 dgp Exp $

	#
	# The implementation is based on namespaces. These naming conventions
	# are followed:
	# Private procs starts with uppercase.
	# Public  procs are exported and starts with lowercase
	#

	# Needed utilities package
	package require opt 0.4.1;

	# Create the safe namespace
	namespace eval ::safe {

	    # Exported API:
	    namespace export interpCreate interpInit interpConfigure interpDelete \
		interpAddToAccessPath interpFindInAccessPath setLogCmd

	    ####
	    #
	    # Setup the arguments parsing
	    #
	    ####

	    # Make sure that our temporary variable is local to this
	    # namespace.  [Bug 981733]
	    variable temp

	    # Share the descriptions
	    set temp [::tcl::OptKeyRegister {
		{-accessPath -list {} "access path for the slave"}
		{-noStatics "prevent loading of statically linked pkgs"}
		{-statics true "loading of statically linked pkgs"}
		{-nestedLoadOk "allow nested loading"}
		{-nested false "nested loading"}
		{-deleteHook -script {} "delete hook"}
	    }]

	    # create case (slave is optional)
	    ::tcl::OptKeyRegister {
		{?slave? -name {} "name of the slave (optional)"}
	    } ::safe::interpCreate
	    # adding the flags sub programs to the command program
	    # (relying on Opt's internal implementation details)
	    lappend ::tcl::OptDesc(::safe::interpCreate) $::tcl::OptDesc($temp)

	    # init and configure (slave is needed)
	    ::tcl::OptKeyRegister {
		{slave -name {} "name of the slave"}
	    } ::safe::interpIC
	    # adding the flags sub programs to the command program
	    # (relying on Opt's internal implementation details)
	    lappend ::tcl::OptDesc(::safe::interpIC) $::tcl::OptDesc($temp)
	    # temp not needed anymore
	    ::tcl::OptKeyDelete $temp


	    # Helper function to resolve the dual way of specifying staticsok
	    # (either by -noStatics or -statics 0)
	    proc InterpStatics {} {
		foreach v {Args statics noStatics} {
		    upvar $v $v
		}
		set flag [::tcl::OptProcArgGiven -noStatics];
		if {$flag && (!$noStatics == !$statics) 
		    && ([::tcl::OptProcArgGiven -statics])} {
		    return -code error\
			"conflicting values given for -statics and -noStatics"
		}
		if {$flag} {
		    return [expr {!$noStatics}]
		} else {
		    return $statics
		}
	    }

	    # Helper function to resolve the dual way of specifying nested loading
	    # (either by -nestedLoadOk or -nested 1)
	    proc InterpNested {} {
		foreach v {Args nested nestedLoadOk} {
		    upvar $v $v
		}
		set flag [::tcl::OptProcArgGiven -nestedLoadOk];
		# note that the test here is the opposite of the "InterpStatics"
		# one (it is not -noNested... because of the wanted default value)
		if {$flag && (!$nestedLoadOk != !$nested) 
		    && ([::tcl::OptProcArgGiven -nested])} {
		    return -code error\
			"conflicting values given for -nested and -nestedLoadOk"
		}
		if {$flag} {
		    # another difference with "InterpStatics"
		    return $nestedLoadOk
		} else {
		    return $nested
		}
	    }

	    ####
	    #
	    #  API entry points that needs argument parsing :
	    #
	    ####


	    # Interface/entry point function and front end for "Create"
	    proc interpCreate {args} {
		set Args [::tcl::OptKeyParse ::safe::interpCreate $args]
		InterpCreate $slave $accessPath \
		    [InterpStatics] [InterpNested] $deleteHook
	    }

	    proc interpInit {args} {
		set Args [::tcl::OptKeyParse ::safe::interpIC $args]
		if {![::interp exists $slave]} {
		    return -code error "\"$slave\" is not an interpreter"
		}
		InterpInit $slave $accessPath \
		    [InterpStatics] [InterpNested] $deleteHook;
	    }

	    proc CheckInterp {slave} {
		if {![IsInterp $slave]} {
		    return -code error \
			"\"$slave\" is not an interpreter managed by ::safe::"
		}
	    }

	    # Interface/entry point function and front end for "Configure"
	    # This code is awfully pedestrian because it would need
	    # more coupling and support between the way we store the
	    # configuration values in safe::interp's and the Opt package
	    # Obviously we would like an OptConfigure
	    # to avoid duplicating all this code everywhere. -> TODO
	    # (the app should share or access easily the program/value
	    #  stored by opt)
	    # This is even more complicated by the boolean flags with no values
	    # that we had the bad idea to support for the sake of user simplicity
	    # in create/init but which makes life hard in configure...
	    # So this will be hopefully written and some integrated with opt1.0
	    # (hopefully for tcl8.1 ?)
	    proc interpConfigure {args} {
		switch [llength $args] {
		    1 {
			# If we have exactly 1 argument
			# the semantic is to return all the current configuration
			# We still call OptKeyParse though we know that "slave"
			# is our given argument because it also checks
			# for the "-help" option.
			set Args [::tcl::OptKeyParse ::safe::interpIC $args]
			CheckInterp $slave
			set res {}
			lappend res [list -accessPath [Set [PathListName $slave]]]
			lappend res [list -statics    [Set [StaticsOkName $slave]]]
			lappend res [list -nested     [Set [NestedOkName $slave]]]
			lappend res [list -deleteHook [Set [DeleteHookName $slave]]]
			join $res
		    }
		    2 {
			# If we have exactly 2 arguments
			# the semantic is a "configure get"
			::tcl::Lassign $args slave arg
			# get the flag sub program (we 'know' about Opt's internal
			# representation of data)
			set desc [lindex [::tcl::OptKeyGetDesc ::safe::interpIC] 2]
			set hits [::tcl::OptHits desc $arg]
			if {$hits > 1} {
			    return -code error [::tcl::OptAmbigous $desc $arg]
			} elseif {$hits == 0} {
			    return -code error [::tcl::OptFlagUsage $desc $arg]
			}
			CheckInterp $slave
			set item [::tcl::OptCurDesc $desc]
			set name [::tcl::OptName $item]
			switch -exact -- $name {
			    -accessPath {
				return [list -accessPath [Set [PathListName $slave]]]
			    }
			    -statics {
				return [list -statics    [Set [StaticsOkName $slave]]]
			    }
			    -nested {
				return [list -nested     [Set [NestedOkName $slave]]]
			    }
			    -deleteHook {
				return [list -deleteHook [Set [DeleteHookName $slave]]]
			    }
			    -noStatics {
				# it is most probably a set in fact
				# but we would need then to jump to the set part
				# and it is not *sure* that it is a set action
				# that the user want, so force it to use the
				# unambigous -statics ?value? instead:
				return -code error\
				    "ambigous query (get or set -noStatics ?)\
				use -statics instead"
			    }
			    -nestedLoadOk {
				return -code error\
				    "ambigous query (get or set -nestedLoadOk ?)\
				use -nested instead"
			    }
			    default {
				return -code error "unknown flag $name (bug)"
			    }
			}
		    }
		    default {
			# Otherwise we want to parse the arguments like init and create
			# did
			set Args [::tcl::OptKeyParse ::safe::interpIC $args]
			CheckInterp $slave
			# Get the current (and not the default) values of
			# whatever has not been given:
			if {![::tcl::OptProcArgGiven -accessPath]} {
			    set doreset 1
			    set accessPath [Set [PathListName $slave]]
			} else {
			    set doreset 0
			}
			if {(![::tcl::OptProcArgGiven -statics]) \
				&& (![::tcl::OptProcArgGiven -noStatics]) } {
			    set statics    [Set [StaticsOkName $slave]]
			} else {
			    set statics    [InterpStatics]
			}
			if {([::tcl::OptProcArgGiven -nested]) \
				|| ([::tcl::OptProcArgGiven -nestedLoadOk]) } {
			    set nested     [InterpNested]
			} else {
			    set nested     [Set [NestedOkName $slave]]
			}
			if {![::tcl::OptProcArgGiven -deleteHook]} {
			    set deleteHook [Set [DeleteHookName $slave]]
			}
			# we can now reconfigure :
			InterpSetConfig $slave $accessPath $statics $nested $deleteHook
			# auto_reset the slave (to completly synch the new access_path)
			if {$doreset} {
			    if {[catch {::interp eval $slave {auto_reset}} msg]} {
				Log $slave "auto_reset failed: $msg"
			    } else {
				Log $slave "successful auto_reset" NOTICE
			    }
			}
		    }
		}
	    }


	    ####
	    #
	    #  Functions that actually implements the exported APIs
	    #
	    ####


	    #
	    # safe::InterpCreate : doing the real job
	    #
	    # This procedure creates a safe slave and initializes it with the
	    # safe base aliases.
	    # NB: slave name must be simple alphanumeric string, no spaces,
	    # no (), no {},...  {because the state array is stored as part of the name}
	    #
	    # Returns the slave name.
	    #
	    # Optional Arguments : 
	    # + slave name : if empty, generated name will be used
	    # + access_path: path list controlling where load/source can occur,
	    #                if empty: the master auto_path will be used.
	    # + staticsok  : flag, if 0 :no static package can be loaded (load {} Xxx)
	    #                      if 1 :static packages are ok.
	    # + nestedok: flag, if 0 :no loading to sub-sub interps (load xx xx sub)
	    #                      if 1 : multiple levels are ok.
	    
	    # use the full name and no indent so auto_mkIndex can find us
	    proc ::safe::InterpCreate {
				       slave 
				       access_path
				       staticsok
				       nestedok
				       deletehook
				   } {
		# Create the slave.
		if {$slave ne ""} {
		    ::interp create -safe $slave
		} else {
		    # empty argument: generate slave name
		    set slave [::interp create -safe]
		}
		Log $slave "Created" NOTICE

		# Initialize it. (returns slave name)
		InterpInit $slave $access_path $staticsok $nestedok $deletehook
	    }


	    #
	    # InterpSetConfig (was setAccessPath) :
	    #    Sets up slave virtual auto_path and corresponding structure
	    #    within the master. Also sets the tcl_library in the slave
	    #    to be the first directory in the path.
	    #    Nb: If you change the path after the slave has been initialized
	    #    you probably need to call "auto_reset" in the slave in order that it
	    #    gets the right auto_index() array values.

	    proc ::safe::InterpSetConfig {slave access_path staticsok\
					      nestedok deletehook} {

		# determine and store the access path if empty
		if {$access_path eq ""} {
		    set access_path [uplevel \#0 set auto_path]
		    # Make sure that tcl_library is in auto_path
		    # and at the first position (needed by setAccessPath)
		    set where [lsearch -exact $access_path [info library]]
		    if {$where == -1} {
			# not found, add it.
			set access_path [concat [list [info library]] $access_path]
			Log $slave "tcl_library was not in auto_path,\
			added it to slave's access_path" NOTICE
		    } elseif {$where != 0} {
			# not first, move it first
			set access_path [concat [list [info library]]\
					     [lreplace $access_path $where $where]]
			Log $slave "tcl_libray was not in first in auto_path,\
			moved it to front of slave's access_path" NOTICE
			
		    }

		    # Add 1st level sub dirs (will searched by auto loading from tcl
		    # code in the slave using glob and thus fail, so we add them
		    # here so by default it works the same).
		    set access_path [AddSubDirs $access_path]
		}

		Log $slave "Setting accessPath=($access_path) staticsok=$staticsok\
		nestedok=$nestedok deletehook=($deletehook)" NOTICE

		# clear old autopath if it existed
		set nname [PathNumberName $slave]
		if {[Exists $nname]} {
		    set n [Set $nname]
		    for {set i 0} {$i<$n} {incr i} {
			Unset [PathToken $i $slave]
		    }
		}

		# build new one
		set slave_auto_path {}
		set i 0
		foreach dir $access_path {
		    Set [PathToken $i $slave] $dir
		    lappend slave_auto_path "\$[PathToken $i]"
		    incr i
		}
		# Extend the access list with the paths used to look for Tcl
		# Modules. We safe the virtual form separately as well, as
		# syncing it with the slave has to be defered until the
		# necessary commands are present for setup.

		set morepaths [::tcl::tm::list]
		while {[llength $morepaths]} {
		    set addpaths $morepaths
		    set morepaths {}

		    foreach dir $addpaths {
			lappend access_path $dir
			Set [PathToken $i $slave] $dir
			lappend slave_auto_path "\$[PathToken $i]"
			lappend slave_tm_path   "\$[PathToken $i]"
			incr i

			# [Bug 2854929]
			# Recursively find deeper paths which may contain
			# modules. Required to handle modules with names like
			# 'platform::shell', which translate into
			# 'platform/shell-X.tm', i.e arbitrarily deep
			# subdirectories. The catch prevents complaints when
			# no paths are added. Do nothing gracefully is 8.6+.

			catch {
			    lappend morepaths {*}[glob -nocomplain -directory $dir -type d *]
			}
		    }
		}

		Set [TmPathListName $slave] $slave_tm_path
		Set $nname $i
		Set [PathListName $slave] $access_path
		Set [VirtualPathListName $slave] $slave_auto_path

		Set [StaticsOkName $slave] $staticsok
		Set [NestedOkName $slave] $nestedok
		Set [DeleteHookName $slave] $deletehook

		SyncAccessPath $slave
	    }

	    #
	    #
	    # FindInAccessPath:
	    #    Search for a real directory and returns its virtual Id
	    #    (including the "$")
	    proc ::safe::interpFindInAccessPath {slave path} {
		set access_path [GetAccessPath $slave]
		set where [lsearch -exact $access_path $path]
		if {$where == -1} {
		    return -code error "$path not found in access path $access_path"
		}
		return "\$[PathToken $where]"
	    }

	    #
	    # addToAccessPath:
	    #    add (if needed) a real directory to access path
	    #    and return its virtual token (including the "$").
	    proc ::safe::interpAddToAccessPath {slave path} {
		# first check if the directory is already in there
		if {![catch {interpFindInAccessPath $slave $path} res]} {
		    return $res
		}
		# new one, add it:
		set nname [PathNumberName $slave]
		set n [Set $nname]
		Set [PathToken $n $slave] $path

		set token "\$[PathToken $n]"

		Lappend [VirtualPathListName $slave] $token
		Lappend [PathListName $slave] $path
		Set $nname [expr {$n+1}]

		SyncAccessPath $slave

		return $token
	    }

	    # This procedure applies the initializations to an already existing
	    # interpreter. It is useful when you want to install the safe base
	    # aliases into a preexisting safe interpreter.
	    proc ::safe::InterpInit {
				     slave 
				     access_path
				     staticsok
				     nestedok
				     deletehook
				 } {

		# Configure will generate an access_path when access_path is
		# empty.
		InterpSetConfig $slave $access_path $staticsok $nestedok $deletehook

		# These aliases let the slave load files to define new commands

		# NB we need to add [namespace current], aliases are always
		# absolute paths.
		::interp alias $slave source {} [namespace current]::AliasSource $slave
		::interp alias $slave load {} [namespace current]::AliasLoad $slave

		# This alias lets the slave use the encoding names, convertfrom,
		# convertto, and system, but not "encoding system <name>" to set
		# the system encoding.

		::interp alias $slave encoding {} [namespace current]::AliasEncoding \
		    $slave

		# Handling Tcl Modules, we need a restricted form of Glob.
		::interp alias $slave glob {} [namespace current]::AliasGlob \
		    $slave

		# This alias lets the slave have access to a subset of the 'file'
		# command functionality.

		AliasSubset $slave file file dir.* join root.* ext.* tail \
		    path.* split

		# This alias interposes on the 'exit' command and cleanly terminates
		# the slave.

		::interp alias $slave exit {} [namespace current]::interpDelete $slave

		# The allowed slave variables already have been set
		# by Tcl_MakeSafe(3)


		# Source init.tcl and tm.tcl into the slave, to get auto_load
		# and other procedures defined:

		# We don't try to use the -rsrc on the mac because it would get
		# confusing if you would want to customize init.tcl
		# for a given set of safe slaves, on all the platforms
		# you just need to give a specific access_path and
		# the mac should be no exception. As there is no
		# obvious full "safe ressources" design nor implementation
		# for the mac, safe interps there will just don't
		# have that ability. (A specific app can still reenable
		# that using custom aliases if they want to).
		# It would also make the security analysis and the Safe Tcl security
		# model platform dependant and thus more error prone.

		if {[catch {::interp eval $slave\
				{source [file join $tcl_library init.tcl]}} msg]} {
		    Log $slave "can't source init.tcl ($msg)"
		    error "can't source init.tcl into slave $slave ($msg)"
		}

		if {[catch {::interp eval $slave \
				{source [file join $tcl_library tm.tcl]}} msg]} {
		    Log $slave "can't source tm.tcl ($msg)"
		    error "can't source tm.tcl into slave $slave ($msg)"
		}

		# Sync the paths used to search for Tcl modules. This can be
		# done only now, after tm.tcl was loaded.
		::interp eval $slave [linsert [Set [TmPathListName $slave]] 0 ::tcl::tm::add]

		return $slave
	    }


	    # Add (only if needed, avoid duplicates) 1 level of
	    # sub directories to an existing path list.
	    # Also removes non directories from the returned list.
	    proc AddSubDirs {pathList} {
		set res {}
		foreach dir $pathList {
		    if {[file isdirectory $dir]} {
			# check that we don't have it yet as a children
			# of a previous dir
			if {[lsearch -exact $res $dir]<0} {
			    lappend res $dir
			}
			foreach sub [glob -directory $dir -nocomplain *] {
			    if {([file isdirectory $sub]) \
				    && ([lsearch -exact $res $sub]<0) } {
				# new sub dir, add it !
				lappend res $sub
			    }
			}
		    }
		}
		return $res
	    }

	    # This procedure deletes a safe slave managed by Safe Tcl and
	    # cleans up associated state:

	    proc ::safe::interpDelete {slave} {

		Log $slave "About to delete" NOTICE

		# If the slave has a cleanup hook registered, call it.
		# check the existance because we might be called to delete an interp
		# which has not been registered with us at all
		set hookname [DeleteHookName $slave]
		if {[Exists $hookname]} {
		    set hook [Set $hookname]
		    if {![::tcl::Lempty $hook]} {
			# remove the hook now, otherwise if the hook
			# calls us somehow, we'll loop
			Unset $hookname
			if {[catch {eval $hook [list $slave]} err]} {
			    Log $slave "Delete hook error ($err)"
			}
		    }
		}

		# Discard the global array of state associated with the slave, and
		# delete the interpreter.

		set statename [InterpStateName $slave]
		if {[Exists $statename]} {
		    Unset $statename
		}

		# if we have been called twice, the interp might have been deleted
		# already
		if {[::interp exists $slave]} {
		    ::interp delete $slave
		    Log $slave "Deleted" NOTICE
		}

		return
	    }

	    # Set (or get) the loging mecanism 

	    proc ::safe::setLogCmd {args} {
		variable Log
		if {[llength $args] == 0} {
		    return $Log
		} else {
		    if {[llength $args] == 1} {
			set Log [lindex $args 0]
		    } else {
			set Log $args
		    }
		}
	    }

	    # internal variable
	    variable Log {}

	    # ------------------- END OF PUBLIC METHODS ------------


	    #
	    # sets the slave auto_path to the master recorded value.
	    # also sets tcl_library to the first token of the virtual path.
	    #
	    proc SyncAccessPath {slave} {
		set slave_auto_path [Set [VirtualPathListName $slave]]
		::interp eval $slave [list set auto_path $slave_auto_path]
		Log $slave "auto_path in $slave has been set to $slave_auto_path"\
		    NOTICE
		::interp eval $slave [list set tcl_library [lindex $slave_auto_path 0]]
	    }

	    # base name for storing all the slave states
	    # the array variable name for slave foo is thus "Sfoo"
	    # and for sub slave {foo bar} "Sfoo bar" (spaces are handled
	    # ok everywhere (or should))
	    # We add the S prefix to avoid that a slave interp called "Log"
	    # would smash our "Log" variable.
	    proc InterpStateName {slave} {
		return "S$slave"
	    }

	    # Check that the given slave is "one of us"
	    proc IsInterp {slave} {
		expr {[Exists [InterpStateName $slave]] && [::interp exists $slave]}
	    }

	    # returns the virtual token for directory number N
	    # if the slave argument is given, 
	    # it will return the corresponding master global variable name
	    proc PathToken {n {slave ""}} {
		if {$slave ne ""} {
		    return "[InterpStateName $slave](access_path,$n)"
		} else {
		    # We need to have a ":" in the token string so
		    # [file join] on the mac won't turn it into a relative
		    # path.
		    return "p(:$n:)"
		}
	    }
	    # returns the variable name of the complete path list
	    proc PathListName {slave} {
		return "[InterpStateName $slave](access_path)"
	    }
	    # returns the variable name of the complete path list
	    proc VirtualPathListName {slave} {
		return "[InterpStateName $slave](access_path_slave)"
	    }
	    # returns the variable name of the complete tm path list
	    proc TmPathListName {slave} {
		return "[InterpStateName $slave](tm_path_slave)"
	    }
	    # returns the variable name of the number of items
	    proc PathNumberName {slave} {
		return "[InterpStateName $slave](access_path,n)"
	    }
	    # returns the staticsok flag var name
	    proc StaticsOkName {slave} {
		return "[InterpStateName $slave](staticsok)"
	    }
	    # returns the nestedok flag var name
	    proc NestedOkName {slave} {
		return "[InterpStateName $slave](nestedok)"
	    }
	    # Run some code at the namespace toplevel
	    proc Toplevel {args} {
		namespace eval [namespace current] $args
	    }
	    # set/get values
	    proc Set {args} {
		eval [linsert $args 0 Toplevel set]
	    }
	    # lappend on toplevel vars
	    proc Lappend {args} {
		eval [linsert $args 0 Toplevel lappend]
	    }
	    # unset a var/token (currently just an global level eval)
	    proc Unset {args} {
		eval [linsert $args 0 Toplevel unset]
	    }
	    # test existance 
	    proc Exists {varname} {
		Toplevel info exists $varname
	    }
	    # short cut for access path getting
	    proc GetAccessPath {slave} {
		Set [PathListName $slave]
	    }
	    # short cut for statics ok flag getting
	    proc StaticsOk {slave} {
		Set [StaticsOkName $slave]
	    }
	    # short cut for getting the multiples interps sub loading ok flag
	    proc NestedOk {slave} {
		Set [NestedOkName $slave]
	    }
	    # interp deletion storing hook name
	    proc DeleteHookName {slave} {
		return [InterpStateName $slave](cleanupHook)
	    }

	    #
	    # translate virtual path into real path
	    #
	    proc TranslatePath {slave path} {
		# somehow strip the namespaces 'functionality' out (the danger
		# is that we would strip valid macintosh "../" queries... :
		if {[regexp {(::)|(\.\.)} $path]} {
		    error "invalid characters in path $path"
		}
		set n [expr {[Set [PathNumberName $slave]]-1}]
		for {} {$n>=0} {incr n -1} {
		    # fill the token virtual names with their real value
		    set [PathToken $n] [Set [PathToken $n $slave]]
		}
		# replaces the token by their value
		subst -nobackslashes -nocommands $path
	    }


	    # Log eventually log an error
	    # to enable error logging, set Log to {puts stderr} for instance
	    proc Log {slave msg {type ERROR}} {
		variable Log
		if {[info exists Log] && [llength $Log]} {
		    eval $Log [list "$type for slave $slave : $msg"]
		}
	    }


	    # file name control (limit access to files/ressources that should be
	    # a valid tcl source file)
	    proc CheckFileName {slave file} {
		# This used to limit what can be sourced to ".tcl" and forbid files
		# with more than 1 dot and longer than 14 chars, but I changed that
		# for 8.4 as a safe interp has enough internal protection already
		# to allow sourcing anything. - hobbs

		if {![file exists $file]} {
		    # don't tell the file path
		    error "no such file or directory"
		}

		if {![file readable $file]} {
		    # don't tell the file path
		    error "not readable"
		}
	    }

	    # AliasGlob is the target of the "glob" alias in safe interpreters.

	    proc AliasGlob {slave args} {
		Log $slave "GLOB ! $args" NOTICE
		set cmd {}
		set at 0

		set dir        {}
		set virtualdir {}

		while {$at < [llength $args]} {
		    switch -glob -- [set opt [lindex $args $at]] {
			-nocomplain -
			-join       { lappend cmd $opt ; incr at }
			-directory  {
			    lappend cmd $opt ; incr at
			    set virtualdir [lindex $args $at]

			    # get the real path from the virtual one.
			    if {[catch {set dir [TranslatePath $slave $virtualdir]} msg]} {
				Log $slave $msg
				return -code error "permission denied"
			    }
			    # check that the path is in the access path of that slave
			    if {[catch {DirInAccessPath $slave $dir} msg]} {
				Log $slave $msg
				return -code error "permission denied"
			    }
			    lappend cmd $dir ; incr at
			}
			pkgIndex.tcl {
			    # Oops, this is globbing a subdirectory in regular
			    # package search. That is not wanted. Abort,
			    # handler does catch already (because glob was not
			    # defined before). See package.tcl, lines 484ff in
			    # tclPkgUnknown.
			    error "unknown command glob"
			}
			-* {
			    Log $slave "Safe base rejecting glob option '$opt'"
			    error      "Safe base rejecting glob option '$opt'"
			}
			default {
			    lappend cmd $opt ; incr at
			}
		    }
		}

		Log $slave "GLOB = $cmd" NOTICE

		if {[catch {eval [linsert $cmd 0 ::interp invokehidden $slave glob]} msg]} {
		    Log $slave $msg
		    return -code error "script error"
		}

		Log $slave "GLOB @ $msg" NOTICE

		# Translate path back to what the slave should see.
		set res {}
		foreach p $msg {
		    regsub -- ^$dir $p $virtualdir p
		    lappend res $p
		}

		Log $slave "GLOB @ $res" NOTICE
		return $res
	    }

	    # AliasSource is the target of the "source" alias in safe interpreters.

	    proc AliasSource {slave args} {

		set argc [llength $args]
		# Allow only "source filename"
		# (and not mac specific -rsrc for instance - see comment in ::init
		# for current rationale)
		if {$argc != 1} {
		    set msg "wrong # args: should be \"source fileName\""
		    Log $slave "$msg ($args)"
		    return -code error $msg
		}
		set file [lindex $args 0]
		
		# get the real path from the virtual one.
		if {[catch {set file [TranslatePath $slave $file]} msg]} {
		    Log $slave $msg
		    return -code error "permission denied"
		}
		
		# check that the path is in the access path of that slave
		if {[catch {FileInAccessPath $slave $file} msg]} {
		    Log $slave $msg
		    return -code error "permission denied"
		}

		# do the checks on the filename :
		if {[catch {CheckFileName $slave $file} msg]} {
		    Log $slave "$file:$msg"
		    return -code error $msg
		}

		# passed all the tests , lets source it:
		if {[catch {::interp invokehidden $slave source $file} msg]} {
		    Log $slave $msg
		    return -code error "script error"
		}
		return $msg
	    }

	    # AliasLoad is the target of the "load" alias in safe interpreters.

	    proc AliasLoad {slave file args} {

		set argc [llength $args]
		if {$argc > 2} {
		    set msg "load error: too many arguments"
		    Log $slave "$msg ($argc) {$file $args}"
		    return -code error $msg
		}

		# package name (can be empty if file is not).
		set package [lindex $args 0]

		# Determine where to load. load use a relative interp path
		# and {} means self, so we can directly and safely use passed arg.
		set target [lindex $args 1]
		if {$target ne ""} {
		    # we will try to load into a sub sub interp
		    # check that we want to authorize that.
		    if {![NestedOk $slave]} {
			Log $slave "loading to a sub interp (nestedok)\
			disabled (trying to load $package to $target)"
			return -code error "permission denied (nested load)"
		    }
		    
		}

		# Determine what kind of load is requested
		if {$file eq ""} {
		    # static package loading
		    if {$package eq ""} {
			set msg "load error: empty filename and no package name"
			Log $slave $msg
			return -code error $msg
		    }
		    if {![StaticsOk $slave]} {
			Log $slave "static packages loading disabled\
			(trying to load $package to $target)"
			return -code error "permission denied (static package)"
		    }
		} else {
		    # file loading

		    # get the real path from the virtual one.
		    if {[catch {set file [TranslatePath $slave $file]} msg]} {
			Log $slave $msg
			return -code error "permission denied"
		    }

		    # check the translated path
		    if {[catch {FileInAccessPath $slave $file} msg]} {
			Log $slave $msg
			return -code error "permission denied (path)"
		    }
		}

		if {[catch {::interp invokehidden\
				$slave load $file $package $target} msg]} {
		    Log $slave $msg
		    return -code error $msg
		}

		return $msg
	    }

	    # FileInAccessPath raises an error if the file is not found in
	    # the list of directories contained in the (master side recorded) slave's
	    # access path.

	    # the security here relies on "file dirname" answering the proper
	    # result.... needs checking ?
	    proc FileInAccessPath {slave file} {

		set access_path [GetAccessPath $slave]

		if {[file isdirectory $file]} {
		    error "\"$file\": is a directory"
		}
		set parent [file dirname $file]

		# Normalize paths for comparison since lsearch knows nothing of
		# potential pathname anomalies.
		set norm_parent [file normalize $parent]
		foreach path $access_path {
		    lappend norm_access_path [file normalize $path]
		}

		if {[lsearch -exact $norm_access_path $norm_parent] == -1} {
		    error "\"$file\": not in access_path"
		}
	    }

	    proc DirInAccessPath {slave dir} {
		set access_path [GetAccessPath $slave]

		if {[file isfile $dir]} {
		    error "\"$dir\": is a file"
		}

		# Normalize paths for comparison since lsearch knows nothing of
		# potential pathname anomalies.
		set norm_dir [file normalize $dir]
		foreach path $access_path {
		    lappend norm_access_path [file normalize $path]
		}

		if {[lsearch -exact $norm_access_path $norm_dir] == -1} {
		    error "\"$dir\": not in access_path"
		}
	    }

	    # This procedure enables access from a safe interpreter to only a subset of
	    # the subcommands of a command:

	    proc Subset {slave command okpat args} {
		set subcommand [lindex $args 0]
		if {[regexp $okpat $subcommand]} {
		    return [eval [linsert $args 0 $command]]
		}
		set msg "not allowed to invoke subcommand $subcommand of $command"
		Log $slave $msg
		error $msg
	    }

	    # This procedure installs an alias in a slave that invokes "safesubset"
	    # in the master to execute allowed subcommands. It precomputes the pattern
	    # of allowed subcommands; you can use wildcards in the pattern if you wish
	    # to allow subcommand abbreviation.
	    #
	    # Syntax is: AliasSubset slave alias target subcommand1 subcommand2...

	    proc AliasSubset {slave alias target args} {
		set pat ^(; set sep ""
			  foreach sub $args {
			      append pat $sep$sub
			      set sep |
			  }
			  append pat )\$
		::interp alias $slave $alias {}\
		    [namespace current]::Subset $slave $target $pat
	    }

	    # AliasEncoding is the target of the "encoding" alias in safe interpreters.

	    proc AliasEncoding {slave args} {

		set argc [llength $args]

		set okpat "^(name.*|convert.*)\$"
		set subcommand [lindex $args 0]

		if {[regexp $okpat $subcommand]} {
		    return [eval [linsert $args 0 \
				      ::interp invokehidden $slave encoding]]
		}

		if {[string first $subcommand system] == 0} {
		    if {$argc == 1} {
			# passed all the tests , lets source it:
			if {[catch {::interp invokehidden \
					$slave encoding system} msg]} {
			    Log $slave $msg
			    return -code error "script error"
			}
		    } else {
			set msg "wrong # args: should be \"encoding system\""
			Log $slave $msg
			error $msg
		    }
		} else {
		    set msg "wrong # args: should be \"encoding option ?arg ...?\""
		    Log $slave $msg
		    error $msg
		}

		return $msg
	    }
	}
    }
}

# ### ### ### ######### ######### #########
## Ready
