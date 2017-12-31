get_dependencies <- function(pkg,extra_deps,verbose=TRUE) {
    # determine dependencies
    dependencies <- r_dependencies_of(description=pkg$description)
    depends <- list()
    # these are used for generating the Depends fields
    as_deb <- function(r,build) {
        return(pkgname_as_debian(paste(dependencies[r,]$name)
                                ,version=dependencies[r,]$version
                                ,repopref=pkg$repo
                                ,build=build))
    }
    depends$bin <- lapply(rownames(dependencies), as_deb, build=F)
    depends$build <- lapply(rownames(dependencies), as_deb, build=T)
    # add the command line dependencies
    depends$bin = c(extra_deps$deb,depends$bin)
    depends$build = c(extra_deps$deb,depends$build)
    # add the system requirements
    if ('SystemRequirements' %in% colnames(pkg$description)) {
        sysreq <- sysreqs_as_debian(pkg$description[1,'SystemRequirements'],verbose=verbose)
	if (!is.null(sysreq) && is.list(sysreq)) {
            depends$bin = c(sysreq$bin,depends$bin)
            depends$build = c(sysreq$build,depends$build)
        } else {
        if (is.null(sysreq)) {
            notice('Houston, we have a NULL sysreq')
            }  else {
	        if (verbose) {cat("sysreq:"); print(sysreq)}
            fail('Cannot interpret system dependency, fix package.\n')
            }
        }
    }

    forced <- forced_deps_as_debian(pkg$name)
    if (length(forced)) {
        notice('forced build dependencies:',paste(forced$build, collapse=', '))
        notice('forced binary dependencies:',paste(forced$bin, collapse=', '))
        depends$bin = c(forced$bin,depends$bin)
        depends$build = c(forced$build,depends$build)
    }

    # make sure we depend upon R in some way...
    if (!length(grep('^r-base',depends$build))) {
        depends$build = c(depends$build,pkgname_as_debian('R',version='>= 2.7.0',build=T))
        depends$bin   = c(depends$bin,  pkgname_as_debian('R',version='>= 2.7.0',build=F))
    }
    # also include stuff to allow tcltk to build (suggested by Dirk)
    depends$build = c(depends$build,'xvfb','xauth','xfonts-base')

    # make all bin dependencies build dependencies.
    depends$build = c(depends$build, depends$bin)

    # remove duplicates
    depends <- lapply(depends,unique)

    # append the Debian dependencies
    depends$build=c(depends$build,'debhelper (>> 4.1.0)','cdbs')
    if (file.exists(file.path(patch_dir, pkg$name))) {
        depends$build <- c(depends$build,'dpatch')
    }
    if (pkg$archdep) {
        depends$bin=c(depends$bin,'${shlibs:Depends}')
    }

    # the names of dependent source packages (to find the .changes file to
    # upload via dput). these can be found recursively.
    depends$r = r_dependency_closure(dependencies)
    # append command line dependencies
    depends$r = c(extra_deps$r, depends$r)
    return(depends)
}

sysreqs_as_debian <- function(sysreq_text,verbose=FALSE) {
    # form of this field is unspecified (ugh) but most people seem to stick
    # with this
    aliases <- c()
    # drop notes
    sysreq_text = gsub('[Nn][Oo][Tt][Ee]:\\s.*','',sysreq_text)
    # conversion from and to commata and lower case
    sysreq_text <- gsub('[[:space:]]and[[:space:]]',' , ',tolower(sysreq_text))
    for (sysreq in strsplit(sysreq_text,'[[:space:]]*,[[:space:]]*')[[1]]) {
	if (verbose) cat("sysreq to investigate: '",sysreq,"'.\n",sep="")
        startreq = sysreq
        # constant case (redundant)
        sysreq = tolower(sysreq)
        # drop version information/comments for now
        sysreq = gsub('[[][^])]*[]]','',sysreq)
        sysreq = gsub('\\([^)]*\\)','',sysreq)
        sysreq = gsub('[[][^])]*[]]','',sysreq)
        sysreq = gsub('version','',sysreq)
        sysreq = gsub('from','',sysreq)
        sysreq = gsub('[<>=]*[[:space:]]*[[:digit:]]+[[:digit:].+:~-]*','',sysreq)
        # byebye URLs
        sysreq = gsub('(ht|f)tps?://[[:alnum:]!?*"\'(),%$_@.&+/=-]*','',sysreq)
        # squish out space -- this does not work for me (did not want to touch, though), Steffen
        sysreq = chomp(gsub('[[:space:]]+',' ',sysreq))
        # no final dot and neither final blanks
        sysreq = gsub('\\.?\\s*$','',sysreq)
        if (nchar(sysreq) == 0) {
            notice('part of the SystemRequirement became nothing')
            next
        }
        alias <- db_sysreq_override(sysreq)
        if (is.null(alias)) {
            error('do not know what to do with SystemRequirement:',sysreq)
            error('original SystemRequirement:',startreq)
            fail('unmet system requirement')
        }
        notice(paste("mapped SystemRequirement '",startreq,"' onto '",alias,"' via '",sysreq,"'.",sep=""))
        aliases = c(aliases,alias)
    }
    return(map_aliases_to_debian(aliases))
}

forced_deps_as_debian <- function(r_name) {
    aliases <- db_get_forced_depends(r_name)
    return(map_aliases_to_debian(aliases))
}

map_aliases_to_debian <- function(aliases) {
    if (!length(aliases)) {
        return(aliases)
    }
    debs <- list()
    debs$bin = unlist(sapply(aliases, db_get_depends))
    debs$build = unlist(sapply(aliases, db_get_depends, build=T))
    debs$bin = debs$bin[debs$bin != 'build-essential']
    debs$build = debs$build[debs$build != 'build-essential']
    return(debs)
}

generate_control <- function(pkg) {
    # construct control file

    control <- data.frame()
    control[1,'Source'] <- pkg$srcname
    control[1,'Section'] <- 'gnu-r'
    control[1,'Priority'] <- 'optional'
    control[1,'Maintainer'] <- maintainer_c2d
    control[1,'Build-Depends'] <- paste(pkg$depends$build, collapse=', ')
    control[1,'Standards-Version'] <- '3.9.1'
    if ('URL' %in% colnames(pkg$description)) {
        control[1,'Homepage'] <- pkg$description[1,'URL']
    }

    control[2,'Package'] <- pkg$debname
    control[2,'Architecture'] <- 'all'
    if (pkg$archdep) {
        control[2,'Architecture'] <- 'any'
    }
    control[2,'Depends'] <- paste(pkg$depends$bin,collapse=', ',sep='')

    # generate the description
    descr <- 'GNU R package "'
    if ('Title' %in% colnames(pkg$description)) {
        descr <- paste(descr,pkg$description[1,'Title'],sep='')
    } else {
        descr <- paste(descr,pkg$name,sep='')
    }
    long_descr <- pkg$description[1,'Description']

    if (length(long_descr) < 1 || long_descr == "") {
        # bypass lintian extended-description-is-empty for which we care not.
        long_descr <- paste('The author/maintainer of this package'
                           ,'did not care to enter a longer description.')
    }

    # using \n\n.\n\n is not very nice, but is necessary to make sure
    # the longer description does not begin on the synopsis line --- R's
    # write.dcf does not appear to have a nicer way of doing this.
    descr <- paste(descr,'"\n\n', long_descr, sep='')
    # add some extra nice info about the original R package
    for (r_info in c('Author','Maintainer')) {
        if (r_info %in% colnames(pkg$description)) {
            descr <- paste(descr,'\n\n',r_info,': ',pkg$description[1,r_info],sep='')
        }
    }
    if (Encoding(descr) == "unknown")
        Encoding(descr) <- "latin1"     # or should it be UTF-8

    control[2,'Description'] <- descr

    # Debian policy says 72 char width; indent minimally
    write.dcf(control,file=pkg$debfile('control.in'),indent=1,width=72)
    write.dcf(control,indent=1,width=72)
}

