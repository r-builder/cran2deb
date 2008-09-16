.First.lib <- function(libname, pkgname) {
    global <- function(name,value) assign(name,value,envir=.GlobalEnv)
    global("which_system", Sys.getenv('CRAN2DEB_SYS','debian-amd64'))
    if (!length(grep('^[a-z]+-[a-z0-9]+$',which_system))) {
        stop('Invalid system specification: must be of the form name-arch')
    }
    global("host_arch", gsub('^[a-z]+-','',which_system))
    global("maintainer", 'cran2deb autobuild <cran2deb@example.org>')
    global("root", system.file(package='cran2deb'))
    global("cache_root", '/var/cache/cran2deb')
    global("pbuilder_results",  file.path('/var/cache/cran2deb/results',which_system))
    global("pbuilder_config",   file.path('/etc/cran2deb/sys',which_system,'pbuilderrc'))
    global("dput_config",       file.path('/etc/cran2deb/sys',which_system,'dput.cf'))
    global("dinstall_config",   file.path('/etc/cran2deb/sys',which_system,'mini-dinstall.conf'))
    global("dinstall_archive",  file.path('/etc/cran2deb/archive',which_system))
    global("r_depend_fields", c('Depends','Imports')) # Suggests, Enhances
    global("scm_revision", 'svn:$Id$')
    global("patch_dir", '/etc/cran2deb/patches')
    global("changesfile", function(srcname,version='*') {
        return(file.path(pbuilder_results
                        ,paste(srcname,'_',version,'_'
                              ,host_arch,'.changes',sep='')))
    })

    cache <- file.path(cache_root,'cache.rda')
    if (file.exists(cache)) {
        load(cache,envir=.GlobalEnv)
    }
    message(paste('I: cran2deb',scm_revision,'building for',which_system))
}
