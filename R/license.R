is_acceptable_license <- function(license,verbose=FALSE,debug=FALSE) {
    if (verbose) cat("is_acceptable_license: license: ",
			#paste(license,collapse="@",sep=""),
			license,
			"'\n",sep="")
    # determine if license text is acceptable

    if (length(grep('^file ',license))) {
        # skip file licenses
	    notice("The package has a file license. This needs individual checking and settings in the respective table (IGNORING).")
        return(TRUE)
    }
    license <- license_text_reduce(license)
    if (debug) cat("**** a ****\n")
    action = db_license_override_name(license)
    if (verbose) {
	cat("**** action: ****\n")
	print(action)
    }
    if (!is.null(action)) {
	if (debug) cat("**** c1 ****\n")
        #return(isTRUE(action))
        return(TRUE)
    }
    if (debug) cat("**** c ****\n")
    license <- license_text_further_reduce(license)
    if (debug) cat("**** d ****\n")
    action = db_license_override_name(license)
    if (debug) cat("**** e ****\n")
    if (!is.null(action)) {
        warn('Accepting/rejecting wild license as',license,'. FIX THE PACKAGE!')
        return(action)
    }
    license <- license_text_extreme_reduce(license)
    if (debug) cat("**** f ****\n")
    action = db_license_override_name(license)
    if (debug) cat("**** g ****\n")
    if (!is.null(action)) {
        warn('Accepting/rejecting wild license as',license,'. FIX THE PACKAGE!')
        return(action)
    }
    error('is_acceptable_license: Wild license',license,'did not match classic rules; rejecting.')
    return(F)
}

license_text_reduce <- function(license,verbose=FALSE,debug=FALSE) {
    if (verbose) cat("license_text_reduce license:",license,"\n",sep="")
    # these reduction steps are sound for all conformant R license
    # specifications.

    if (Encoding(license) == "unknown")
        Encoding(license) <- "latin1"   # or should it be UTF-8 ?

    ## compress spaces into a single space
    license = gsub('[[:space:]]+',' ',license)
    # make all characters lower case
    license = tolower(license)
    # don't care about versions of licenses
    license = chomp(sub('\\( ?[<=>!]+ ?[0-9.-]+ ?\\)',''
                    ,sub('-[0-9.-]+','',license)))
    # remove any extra space introduced
    license = chomp(gsub('[[:space:]]+',' ',license))
    if (debug) cat("license_text_reduce: ",license,"\n",sep="")
    return(license)
}

license_text_further_reduce <- function(license,verbose=TRUE) {
    if (verbose) cat("license_text_further_reduce license:",license,"\n",sep="")
    # these reduction steps are heuristic and may lead to
    # in correct acceptances, if care is not taken.

    # uninteresting urls
    license = gsub('http://www.gnu.org/[[:alnum:]/._-]*','',license)
    license = gsub('http://www.x.org/[[:alnum:]/._-]*','',license)
    license = gsub('http://www.opensource.org/[[:alnum:]/._-]*','',license)
    # remove all punctuation
    license = gsub('[[:punct:]]+','',license)
    # remove any extra space introduced
    license = chomp(gsub('[[:space:]]+',' ',license))
    # redundant
    license = gsub('the','',license)
    license = gsub('see','',license)
    license = gsub('standard','',license)
    license = gsub('licen[sc]e','',license)
    license = gsub('(gnu )?(gpl|general public)','gpl',license)
    license = gsub('(mozilla )?(mpl|mozilla public)','mpl',license)
    # remove any extra space introduced
    license = chomp(gsub('[[:space:]]+',' ',license))
    return(license)
}

license_text_extreme_reduce <- function(license,verbose=TRUE) {
    if (verbose) cat("license_text_extreme_reduce license:",license,"\n",sep="")
    # remove everything that may or may not be a version specification
    license = gsub('(ver?sion|v)? *[0-9.-]+ *(or *(higher|later|newer|greater|above))?',''
                   ,license)
    # remove any extra space introduced
    license = chomp(gsub('[[:space:]]+',' ',license))
    return(license)
}

license_text_hash_reduce <- function(text,verbose=TRUE) {
    if (verbose) cat("license_text_hash_reduce text:",text,"\n",sep="")
    # reduction of license text, suitable for hashing.
    return(chomp(tolower(gsub('[[:space:]]+',' ',text))))
}

get_license <- function(pkg,license,verbose=FALSE) {
    license <- gsub('[[:space:]]+$',' ',license)
    if (length(grep('^file\\s',license))) {
        notice("License recognised as 'file'-based license.")
        if (length(grep('^file\\s+LICEN[CS]E$',license))) {
            file = gsub('file\\s+','',license)
            path = file.path(pkg$path, file)
            if (file.exists(path)) {
                license <- readChar(path,file.info(path)$size)
            } else {
                path = file.path(pkg$path, 'inst', file)
                if (file.exists(path)) {
                    license <- readChar(path,file.info(path)$size)
                } else {
                    error(paste("Could not locate license file expected at '",
				path,"' or at '",
				file.path(pkg$path, file),"'.\n",sep=""))
                }
            }
        } else {
            error("invalid license file specification, expected 'LICENSE' as filename, got: ",license)
            return(NA)
        }
    }
    return(license)
}

get_license_hash <- function(pkg,license,verbose=FALSE) {
    return(digest(get_license(pkg,license,verbose=verbose),algo='sha1',serialize=FALSE))
}

is_acceptable_hash_license <- function(pkg,license,verbose=TRUE,debug=TRUE) {
    if (debug) cat(paste("is_acceptable_hash_license: pkg$name='",pkg$name,"', license='",license,"'.\n",sep=""))
    license_sha1 <- get_license_hash(pkg,license,verbose=verbose)
    if (is.null(license_sha1)) {
	if (verbose) cat("is_acceptable_hash_license: get_license_hash(pkg,license) returned NULL, returning FALSE.\n")
        return(FALSE)
    } else if (verbose) {
        notice(paste("is_acceptable_hash_license, license_sha1 determined: '",license_sha1,"'",sep=""))
    }
    action = db_license_override_hash(license_sha1)
    if (is.null(action)) {
	if (verbose) cat("is_acceptable_hash_license: get_license_override_hash(license_sha1) returned NULL, returning FALSE.\n")
        action = FALSE
    } else if (0 == length(action)) {
	notice("An error occurred, 0==length(action), ignoring package.\n")
	action = FALSE
    } else if (is.na(action)) {
	notice("An error occurred, is.na(action), ignoring package.\n")
	action = FALSE
    }
    if (action) {
        warn('Wild license',license,'accepted via hash',license_sha1)
    }
    return(action)
}


accept_license <- function(pkg,verbose=TRUE) {
    # check the license
    if (!('License' %in% names(pkg$description[1,]))) {
        fail('package has no License: field in description!')
	return(NULL)
    }
    accept=NULL
    if (verbose) { cat("accept_license: pkg:\n"); print(pkg$srcname) }
    license<-pkg$description[1,'License']
    if (verbose) { cat("                license:\n"); print(license) }
    
    for (l in strsplit(chomp(license),'[[:space:]]*\\|[[:space:]]*')[[1]]) {
	if (verbose) cat("Investigating: '",l,"'\n",sep="")
        if (is_acceptable_license(l)) {
            accept=l
            break
        } else if (is_acceptable_hash_license(pkg,l,verbose=verbose)) {
            accept=l
            break
        } else {
	    notice(paste("Could not accept license ",l," for package ",pkg,"\n",sep=""))
	}
    }
    if (is.null(accept)) {
        fail('No acceptable license:',pkg$description[1,'License'])
    } else {
        notice('Auto-accepted license',accept)
    }
    if (accept == 'Unlimited') {
        # definition of Unlimited from ``Writing R extensions''
        accept=paste('Unlimited (no restrictions on distribution or'
                    ,'use other than those imposed by relevant laws)')
    }
    return(accept)
}
