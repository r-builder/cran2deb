
build <- function(name,extra_deps,force=F,do_cleanup=T) {
    # can't, and hence don't need to, build base packages
    if (name %in% base_pkgs) {
        return(T)
    }
    log_clear()
    dir <- setup()

    # obtain the Debian version-to-be
    version <- try(new_build_version(name))
    if (inherits(version,'try-error')) {
        error('failed to build in new_build_version: ',name)
        return(NULL)
    }
	
#	if (name == "sp"){
#		version <- paste("1:",version,sep="")
#		}
	
    result <- try((function() {
        if (!force && !needs_build(name,version)) {
            notice('skipping build of',name)
            return(NULL)
        }

        if (name %in% db_blacklist_packages()) {
            #fail('package',name,'is blacklisted. consult database for reason.')
            notice('package',name,'is blacklisted. consult database for reason.')
            return(NULL)
        }

        pkg <- prepare_new_debian(prepare_pkg(dir,name),extra_deps)
        if (pkg$debversion != version) {
            fail('expected Debian version',version,'not equal to actual version',pkg$debversion)
        }

        # delete notes of upload
        file.remove(Sys.glob(file.path(pbuilder_results,'*.upload')))

        notice('R dependencies:',paste(pkg$depends$r,collapse=', '))
	#if (debug) notice(paste("build_debian(",pkg,") invoked\n",sep=""))

        build_debian(pkg)
	#if (debug) notice(paste("build_debian(",pkg,") completed.\n",sep=""))


        # upload the package
	notice("Package upload")
##         ret = log_system('umask 002;dput','-c',shQuote(dput_config),'local' ,changesfile(pkg$srcname,pkg$debversion))

#	cmd = paste('umask 002; cd /var/www/cran2deb/rep && reprepro -b . include testing', changesfile(pkg$srcname,pkg$debversion),sep=" ")
    cmd = paste('umask 002; cd /var/www/cran2deb/rep && reprepro --ignore=wrongdistribution --ignore=missingfile -b . include rbuilders', changesfilesrc(pkg$srcname,pkg$debversion,dir),sep=" ")
	notice('Executing: ',cmd)
        #if (verbose) notice('Executing: ',cmd)
        ret = log_system(cmd)
        if (ret != 0) {
            #fail('upload failed!')
	    notice("Upload failed, ignored.")
        } else {
	    notice("Upload successful.")
	}
##         # wait for mini-dinstall to get to work
##         upload_success = FALSE
##         for (i in seq(1,12)) {
##             if (file.exists(file.path(dinstall_archive,'testing',paste(pkg$srcname, '_', pkg$version, '.orig.tar.gz', sep='')))) {
##                 upload_success = TRUE
##                 break
##             }
##             warn(i,'/12: does not exist',file.path(dinstall_archive,'testing',paste(pkg$srcname, '_', pkg$version, '.orig.tar.gz', sep='')))

##             Sys.sleep(5)
##         }
##         if (!upload_success) {
##             warn('upload took too long; continuing as normal (some builds may fail temporarily)')
##         }
        return(pkg$debversion)
    })())
    if (do_cleanup) {
        cleanup(dir)
    } else {
        notice('output is in',dir,'. you must clean this up yourself.')
    }
    if (is.null(result)) {
        # nothing was done so escape asap.
        return(result)
    }

    # otherwise record progress
    failed = inherits(result,'try-error')
    if (failed) {
        error('failure of',name,'means these packages will fail:'
                     ,paste(r_dependency_closure(name,forward_arcs=F),collapse=', '))
    }
    db_record_build(name, version, log_retrieve(), !failed)
    return(!failed)
}

needs_build <- function(name,version) {
    # see if the last build was successful
    # Check to see if current version is available in a PPA or repository
#    debname <- pkgname_as_debian(name,binary=T)
#    ubuntu.version <- strsplit(readLines(pipe('lsb_release -c')),"\t")[[1]][2]
#    cmd <- paste('apt-cache show --no-all-versions',debname,'| grep  Version')
#    aval.version <- readLines(pipe(cmd))
#    u.version <- strsplit(try(new_build_version(name)),"cran")[[1]][1]
#    closeAllConnections()
#    if (length(aval.version)>0) {
#      aval.version <- strsplit(aval.version,ubuntu.version)[[1]][1]
#      aval.version <- strsplit(aval.version,": ")[[1]][2]
#      aval.version <- strsplit(aval.version,"cran")[[1]][1]
#      aval.version
#      if (gsub("-",".",u.version) == gsub("-",".",aval.version)) {
#        notice('Current version of',name,'exists in MAIN, CRAN, or PPA')
#        return(F)
#      } else {
#        notice('Older version of',name,'exists in MAIN, CRAN, or PPA')
#      }
#    }
    build <- db_latest_build(name)
    if (!is.null(build) && build$success) {
        # then something must have changed for us to attempt this
        # build
        if (build$r_version == version_upstream(version) &&
            build$deb_epoch == version_epoch(version) &&
            build$db_version == db_get_version()) {
            return(F)
        }
    } else {
        # always rebuild on failure or no record
        notice('rebuilding',name,': no build record or previous build failed')
        return(T)
    }
    # see if it has already been built *and* successfully uploaded
    srcname <- pkgname_as_debian(name,binary=F)
    debname <- pkgname_as_debian(name,binary=T)
    if (file.exists(changesfile(srcname, version))) {
        notice('already built',srcname,'version',version)
        return(F)
    }

    if (build$r_version != version_upstream(version)) {
        notice('rebuilding',name,': new upstream version',build$r_version,'(old) vs',version_upstream(version),'(new)')
    }
    if (build$deb_epoch != version_epoch(version)) {
        notice('rebuilding',name,': new cran2deb epoch',build$deb_epoch,'(old) vs',version_epoch(version),'(new)')
    }
    if (build$db_version != db_get_version()) {
        notice('rebuilding',name,': new db version',build$db_version,'(old) vs',db_get_version(),'(new)')
    }
    notice(paste("Now deleting ",debname,", ",srcname,".\n",sep=""))
    rm(debname,srcname)
    return(T)
}

build_debian <- function(pkg) {
    wd <- getwd()
    #notice(paste("Now in path ",wd,"\n",sep=""))
    setwd(pkg$path)
    
    notice('building Debian source package', pkg$debname, paste('(', pkg$debversion,')', sep=''), 'in', getwd(), '...')

    cmd = paste('debuild -us -uc -sa -S -d')
    if (version_revision(pkg$debversion) > 2) {
        cmd = paste(cmd,'-sd')
        notice('build should exclude original source')
    }
    notice(paste("Executing ",'"',cmd,'"'," from directory '",getwd(),"'.\n",sep=""))
    ret = log_system(cmd)
    setwd(wd)
    if (ret != 0) {
        fail('Failed to build source package.')
    }
    return(ret);
}

changesfilesrc <- function(srcname,version='*',dir) {
        return(file.path(dir
                        ,paste(srcname,'_',version,'_'
                              ,'source','.changes',sep='')))
    }

needs_upload <- function(name,version) {
    # Check to see if current version is available in a PPA or repository
    debname <- pkgname_as_debian(name,binary=T)
    ubuntu.version <- strsplit(readLines(pipe('lsb_release -c')),"\t")[[1]][2]
    cmd <- paste('apt-cache show --no-all-versions',debname,'| grep  Version')
    aval.version <- readLines(pipe(cmd))
    u.version <- strsplit(version,"cran")[[1]][1]
    if (length(aval.version)>0) {
      aval.version <- strsplit(aval.version,ubuntu.version)[[1]][1]
      aval.version <- strsplit(aval.version,": ")[[1]][2]
      aval.version <- strsplit(aval.version,"cran")[[1]][1]
      if (gsub("-",".",u.version) == gsub("-",".",aval.version)) {
        notice('Current version of',name,'exists in MAIN, CRAN, or PPA')
        closeAllConnections()
        return(F)
      } else {
        notice('Older version of',name,'exists in MAIN, CRAN, or PPA')
        closeAllConnections()
        return(T)
      }
    } else {
      notice('No version of',name,'exisits in MAIN, CRAN, or PPA')
      closeAllConnections()
      return(T)
    }
}
