append_build_from_pkg <- function(pkg, builds) {
    pkg_build <- data.frame(id = -1     # never used
                           ,package = pkg$name
                           ,system = which_system
                           ,r_version = version_upstream(pkg$debversion)
                           ,deb_epoch = version_epoch(pkg$debversion)
                           ,deb_revision = version_revision(pkg$debversion)
                           ,db_version = db_get_version()
                           ,date_stamp = pkg$date_stamp
                           ,scm_revision = scm_revision
                           ,success = 1 # never used
                           ,log = ''    # never used
                           )
    return(cbind(data.frame(srcname=pkg$srcname), rbind(builds, pkg_build)))
}

generate_changelog <- function(pkg) {
    # TODO: ``Writing R extensions'' mentions that a package may also have
    # {NEWS,ChangeLog} files.
    builds <- append_build_from_pkg(pkg, db_builds(pkg$name))
    sapply(rev(rownames(builds)), function(b, changelog) generate_changelog_entry(builds[b,], changelog), pkg$debfile('changelog.in'))
}

generate_changelog_entry <- function(build, changelog) {
    # TODO: should say 'New upstream release' when necessary
    debversion <- version_new(build$r_version, build$deb_revision, build$deb_epoch)
    cat(paste(paste(build$srcname,' (',debversion,') testing; urgency=low',sep='')
             ,'' ,paste('  * cran2deb ',build$scm_revision
                       ,' with DB version ',as.integer(build$db_version),'.',sep='')
             ,'',paste(' --',maintainer,'',format(build$date_stamp,'%a, %d %b %Y %H:%M:%S %z'))
             ,'','','',sep='\n'),file=changelog, append=TRUE)
}

generate_rules <- function(pkg) {
    cat(paste('#!/usr/bin/make -f'
             ,paste('debRreposname :=',pkg$repo)
             ,'include /usr/share/R/debian/r-cran.mk'
             ,'',sep='\n')
       ,file=pkg$debfile('rules'))
    if (pkg$name %in% c("Rmpi", "npRmpi")) {
        cat("extraInstallFlags=\"--no-test-load\"\n", file=pkg$debfile('rules'), append=TRUE)
    }      
    Sys.chmod(pkg$debfile('rules'),'0700')
}

generate_copyright <- function(pkg) {
    # generate_copyright file; we trust DESCRIPTION

    # if maintainer is missing then try to use author
    if (!('Maintainer' %in% colnames(pkg$description))) {
        if ('Author' %in% colnames(pkg$description)) {
            maintainer = pkg$description[1,'Author']
        } else {
            fail('Maintainer and Author not defined in R DESCRIPTION')
        }
    } else {
        maintainer = pkg$description[1,'Maintainer']
    }
    # likewise if author is missing then try to use maintainer
    if (!('Author' %in% colnames(pkg$description))) {
        author = maintainer
    } else {
        author = pkg$description[1,'Author']
    }

    writeLines(strwrap(
        paste('This Debian package of the GNU R package',pkg$name
             ,'was generated automatically using cran2deb by'
             ,paste(maintainer,'.',sep='')
             ,''
             ,'The original GNU R package is Copyright (C) '
             # TODO: copyright start date, true copyright date
             ,format(Sys.time(),'%Y')
             ,author
             ,'and possibly others.'
             ,''
             ,'The original GNU R package is maintained by'
             ,maintainer,'and was obtained from:'
             ,''
             ,pkg$repoURL
             ,''
             ,''
             ,'The GNU R package DESCRIPTION offers a'
             ,'Copyright licenses under the terms of the license:'
             ,pkg$license,'.  On a Debian GNU/Linux system, common'
             ,'licenses are included in the directory'
             ,'/usr/share/common-licenses/.'
             ,''
             ,'The DESCRIPTION file for the original GNU R package '
             ,'can be found in '
             ,file.path('/usr/lib/R/site-library'
                   ,pkg$debname
                   ,'DESCRIPTION'
                   )
             ,sep='\n'), width=72), con=pkg$debfile('copyright.in'))
}

prepare_new_debian <- function(pkg,extra_deps) {
    # generate Debian version and name
    pkg$debversion = new_build_version(pkg$name)

    # make the debian/ directory
    debdir <- file.path(pkg$path,'debian')
    pkg$debfile <- function(x) { file.path(debdir,x) }
    unlink(debdir,recursive=T)
    dir.create(debdir)

    # see if this is an architecture-dependent package.
    # heuristic: if /src/ exists in pkg$path, then this is an
    #            architecture-dependent package.
    # CRAN2DEB.pm is a bit fancier about this but ``Writing R extensions''
    # says: ``The sources and headers for the compiled code are in src, plus
    # optionally file Makevars or Makefile.'' It seems unlikely that
    # architecture independent code would end up here.
    pkg$archdep = file.exists(file.path(pkg$path,'src'))
    pkg$arch <- 'all'
    if (pkg$archdep) {
        pkg$arch <- host_arch()
    }

    pkg$license <- accept_license(pkg)
    pkg$depends <- get_dependencies(pkg,extra_deps)
    apply_patches(pkg)
    generate_lintian(pkg)
    generate_changelog(pkg)
    generate_rules(pkg)
    generate_copyright(pkg)
    generate_control(pkg)
    ## debdir <- file.path(pkg$path,'debian')
    ## system(paste("ls ", debdir, "; ls -l ", debdir, "/patches/*", sep=""))

    # convert text to utf8 (who knows what the original character set is --
    # let's hope iconv DTRT).
    for (file in c('control','changelog','copyright')) {
        log_system('iconv -o ',shQuote(pkg$debfile(file))
                    ,' -t utf8 -c '
                    ,shQuote(pkg$debfile(paste(file,'in',sep='.'))))
        file.remove(pkg$debfile(paste(file,'in',sep='.')))
    }
    return(pkg)
}
