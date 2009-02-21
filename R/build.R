
build <- function(name,extra_deps,force=F) {
    # can't, and hence don't need to, build base packages
    if (name %in% base_pkgs) {
        return(T)
    }
    log_clear()
    dir <- setup()

    # obtain the Debian version-to-be
    version <- try(new_build_version(name))
    if (inherits(version,'try-error')) {
        error('failed to build',name)
        return(NULL)
    }

    result <- try((function() {
        if (!force && !needs_build(name,version)) {
            notice('skipping build of',name)
            return(NULL)
        }

        pkg <- prepare_new_debian(prepare_pkg(dir,name),extra_deps)
        if (pkg$debversion != version) {
            fail('expected Debian version',version,'not equal to actual version',pkg$debversion)
        }

        # delete notes of upload
        file.remove(Sys.glob(file.path(pbuilder_results,'*.upload')))

        notice('R dependencies:',paste(pkg$depends$r,collapse=', '))
        build_debian(pkg)

        # upload the package
        ret = log_system('umask 002;dput','-c',shQuote(dput_config),'local'
                    ,changesfile(pkg$srcname,pkg$debversion))
        if (ret != 0) {
            fail('upload failed!')
        }

        return(pkg$debversion)
    })())
    cleanup(dir)
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
    # see if it has already been built
    srcname <- pkgname_as_debian(name,binary=F)
    debname <- pkgname_as_debian(name,binary=T)
    if (file.exists(changesfile(srcname, version))) {
        notice('already built',srcname,'version',version)
        return(F)
    }

    # XXX: what about building newer versions of Debian packages?
    if (debname %in% debian_pkgs) {
        notice(srcname,' exists in Debian (perhaps a different version)')
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
    rm(debname,srcname)
    return(T)
}

build_debian <- function(pkg) {
    wd <- getwd()
    setwd(pkg$path)
    notice('building Debian package'
                 ,pkg$debname
                 ,paste('(',pkg$debversion,')',sep='')
                 ,'...')

    cmd = paste('pdebuild --configfile',shQuote(pbuilder_config))
    if (version_revision(pkg$debversion) > 2) {
        cmd = paste(cmd,'--debbuildopts','-sd')
        notice('build should exclude original source')
    }
    ret = log_system(cmd)
    setwd(wd)
    if (ret != 0) {
        fail('Failed to build package.')
    }
}

