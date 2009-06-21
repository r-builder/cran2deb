
db_start <- function() {
    drv <- dbDriver('SQLite')
    con <- dbConnect(drv, dbname=file.path(cache_root,'cran2deb.db'))
    if (!dbExistsTable(con,'sysreq_override')) {
        dbGetQuery(con,paste('CREATE TABLE sysreq_override ('
                  ,' depend_alias TEXT NOT NULL'
                  ,',r_pattern TEXT PRIMARY KEY NOT NULL'
                  ,')'))
    }
    if (!dbExistsTable(con,'debian_dependency')) {
        dbGetQuery(con,paste('CREATE TABLE debian_dependency ('
                  ,' id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL'
                  ,',alias TEXT NOT NULL'
                  ,',build INTEGER NOT NULL'
                  ,',debian_pkg TEXT NOT NULL'
                  ,',UNIQUE (alias,build,debian_pkg)'
                  ,')'))
    }
    if (!dbExistsTable(con,'forced_depends')) {
        dbGetQuery(con,paste('CREATE TABLE forced_depends ('
                  ,' r_name TEXT NOT NULL'
                  ,',depend_alias TEXT NOT NULL'
                  ,',PRIMARY KEY (r_name,depend_alias)'
                  ,')'))
    }
    if (!dbExistsTable(con,'license_override')) {
        dbGetQuery(con,paste('CREATE TABLE license_override ('
                  ,' name TEXT PRIMARY KEY NOT NULL'
                  ,',accept INT NOT NULL'
                  ,')'))
    }
    if (!dbExistsTable(con,'license_hashes')) {
        dbGetQuery(con,paste('CREATE TABLE license_hashes ('
                  ,' name TEXT NOT NULL'
                  ,',sha1 TEXT PRIMARY KEY NOT NULL'
                  ,')'))
    }
    if (!dbExistsTable(con,'database_versions')) {
        dbGetQuery(con,paste('CREATE TABLE database_versions ('
                  ,' version INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL'
                  ,',version_date INTEGER NOT NULL'
                  ,',base_epoch INTEGER NOT NULL'
                  ,')'))
        db_add_version(con,1,0)
    }
    if (!dbExistsTable(con,'packages')) {
        dbGetQuery(con,paste('CREATE TABLE packages ('
                  ,' package TEXT PRIMARY KEY NOT NULL'
                  ,',latest_r_version TEXT'
                  ,')'))
    }
    if (!dbExistsTable(con,'builds')) {
        dbGetQuery(con,paste('CREATE TABLE builds ('
                  ,' id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL'
                  ,',system TEXT NOT NULL'
                  ,',package TEXT NOT NULL'
                  ,',r_version TEXT NOT NULL'
                  ,',deb_epoch INTEGER NOT NULL'
                  ,',deb_revision INTEGER NOT NULL'
                  ,',db_version INTEGER NOT NULL'
                  ,',date_stamp TEXT NOT NULL'
                  ,',time_stamp TEXT NOT NULL'
                  ,',scm_revision TEXT NOT NULL'
                  ,',success INTEGER NOT NULL'
                  ,',log TEXT'
                  ,',UNIQUE(package,system,r_version,deb_epoch,deb_revision,db_version)'
                  ,')'))
    }
    if (!dbExistsTable(con,'blacklist_packages')) {
        dbGetQuery(con,paste('CREATE TABLE blacklist_packages ('
                  ,' package TEXT PRIMARY KEY NOT NULL '
                  ,',nonfree INTEGER NOT NULL DEFAULT 0'
                  ,',obsolete INTEGER NOT NULL DEFAULT 0'
                  ,',broken_dependency INTEGER NOT NULL DEFAULT 0'
                  ,',unsatisfied_dependency INTEGER NOT NULL DEFAULT 0'
                  ,',breaks_cran2deb INTEGER NOT NULL DEFAULT 0'
                  ,',explanation TEXT NOT NULL '
                  ,')'))
    }
    return(con)
}

db_stop <- function(con,bump=F) {
    if (bump) {
        db_bump(con)
    }
    dbDisconnect(con)
}

db_quote <- function(text) {
    return(paste('\'', gsub('([\'"])','\\1\\1',text),'\'',sep=''))
}

db_now <- function() {
    return(as.integer(gsub('-','',Sys.Date())))
}

db_cur_version <- function(con) {
    return(as.integer(dbGetQuery(con, 'SELECT max(version) FROM database_versions')[[1]]))
}

db_base_epoch <- function(con) {
    return(as.integer(dbGetQuery(con,
        paste('SELECT max(base_epoch) FROM database_versions'
             ,'WHERE version IN (SELECT max(version) FROM database_versions)'))[[1]]))
}

db_get_base_epoch <- function() {
    con <- db_start()
    v <- db_base_epoch(con)
    db_stop(con)
    return(v)
}

db_get_version <- function() {
    con <- db_start()
    v <- db_cur_version(con)
    db_stop(con)
    return(v)
}

db_add_version <- function(con, version, epoch) {
    dbGetQuery(con,paste('INSERT INTO database_versions (version,version_date,base_epoch)'
              ,'VALUES (',as.integer(version),',',db_now(),',',as.integer(epoch),')'))
}

db_bump <- function(con) {
    db_add_version(con,db_cur_version(con)+1, db_base_epoch(con))
}

db_bump_epoch <- function(con) {
    db_add_version(con,db_cur_version(con)+1, db_base_epoch(con)+1)
}

db_sysreq_override <- function(sysreq_text) {
    con <- db_start()
    results <- dbGetQuery(con,paste(
                    'SELECT DISTINCT depend_alias FROM sysreq_override WHERE'
                            ,db_quote(tolower(sysreq_text)),'LIKE r_pattern'))
    db_stop(con)
    if (length(results) == 0) {
        return(NULL)
    }
    return(results$depend_alias)
}

db_add_sysreq_override <- function(pattern,depend_alias) {
    con <- db_start()
    results <- dbGetQuery(con,paste(
                     'INSERT OR REPLACE INTO sysreq_override'
                    ,'(depend_alias, r_pattern) VALUES ('
                    ,' ',db_quote(tolower(depend_alias))
                    ,',',db_quote(tolower(pattern))
                    ,')'))
    db_stop(con)
}

db_sysreq_overrides <- function() {
    con <- db_start()
    overrides <- dbGetQuery(con,paste('SELECT * FROM sysreq_override'))
    db_stop(con)
    return(overrides)
}

db_get_depends <- function(depend_alias,build=F) {
    con <- db_start()
    results <- dbGetQuery(con,paste(
                    'SELECT DISTINCT debian_pkg FROM debian_dependency WHERE'
                    ,db_quote(tolower(depend_alias)),'= alias'
                    ,'AND',as.integer(build),'= build'))
    db_stop(con)
    return(results$debian_pkg)
}

db_add_depends <- function(depend_alias,debian_pkg,build=F) {
    con <- db_start()
    results <- dbGetQuery(con,paste(
                     'INSERT OR REPLACE INTO debian_dependency'
                    ,'(alias, build, debian_pkg) VALUES ('
                    ,' ',db_quote(tolower(depend_alias))
                    ,',',as.integer(build)
                    ,',',db_quote(tolower(debian_pkg))
                    ,')'))
    db_stop(con)
}

db_depends <- function() {
    con <- db_start()
    depends <- dbGetQuery(con,paste('SELECT * FROM debian_dependency'))
    db_stop(con)
    return(depends)
}

db_get_forced_depends <- function(r_name) {
    con <- db_start()
    forced_depends <- dbGetQuery(con,
                paste('SELECT depend_alias FROM forced_depends WHERE'
                     ,db_quote(r_name),'= r_name'))
    db_stop(con)
    return(forced_depends$depend_alias)
}

db_add_forced_depends <- function(r_name, depend_alias) {
    if (!length(db_get_depends(depend_alias,build=F)) &&
        !length(db_get_depends(depend_alias,build=T))) {
        fail('Debian dependency alias',depend_alias,'is not know,'
                  ,'yet trying to force a dependency on it?')
    }
    con <- db_start()
    dbGetQuery(con,
            paste('INSERT OR REPLACE INTO forced_depends (r_name, depend_alias)'
                 ,'VALUES (',db_quote(r_name),',',db_quote(depend_alias),')'))
    db_stop(con)
}

db_forced_depends <- function() {
    con <- db_start()
    depends <- dbGetQuery(con,paste('SELECT * FROM forced_depends'))
    db_stop(con)
    return(depends)
}

db_license_override_name <- function(name) {
    con <- db_start()
    results <- dbGetQuery(con,paste(
                    'SELECT DISTINCT accept FROM license_override WHERE'
                            ,db_quote(tolower(name)),'= name'))
    db_stop(con)
    if (length(results) == 0) {
        return(NULL)
    }
    return(as.logical(results$accept))
}

db_add_license_override <- function(name,accept) {
    notice('adding',name,'accept?',accept)
    if (accept != TRUE && accept != FALSE) {
        fail('accept must be TRUE or FALSE')
    }
    con <- db_start()
    results <- dbGetQuery(con,paste(
                     'INSERT OR REPLACE INTO license_override'
                    ,'(name, accept) VALUES ('
                    ,' ',db_quote(tolower(name))
                    ,',',as.integer(accept)
                    ,')'))
    db_stop(con)
}

db_license_override_hash <- function(license_sha1) {
    con <- db_start()
    results <- dbGetQuery(con,paste(
                     'SELECT DISTINCT accept FROM license_override'
                    ,'INNER JOIN license_hashes'
                    ,'ON license_hashes.name = license_override.name WHERE'
                    ,db_quote(tolower(license_sha1)),'= license_hashes.sha1'))
    db_stop(con)
    if (length(results) == 0) {
        return(NULL)
    }
    return(as.logical(results$accept))
}

db_license_overrides <- function() {
    con <- db_start()
    overrides <- dbGetQuery(con,paste('SELECT * FROM license_override'))
    hashes    <- dbGetQuery(con,paste('SELECT * FROM license_hashes'))
    db_stop(con)
    return(list(overrides=overrides,hashes=hashes))
}

db_add_license_hash <- function(name,license_sha1) {
    if (is.null(db_license_override_name(name))) {
        fail('license',name,'is not know, yet trying to add a hash for it?')
    }
    notice('adding hash',license_sha1,'for',name)
    con <- db_start()
    dbGetQuery(con,paste(
         'INSERT OR REPLACE INTO license_hashes'
        ,'(name, sha1) VALUES ('
        ,' ',db_quote(tolower(name))
        ,',',db_quote(tolower(license_sha1))
        ,')'))
    db_stop(con)
}


db_update_package_versions <- function() {
    # seems like the quickest way of doing this:
    con <- db_start()
    dbGetQuery(con, 'DROP TABLE packages')
    db_stop(con)
    # db_start re-makes all tables
    con <- db_start()
    for (package in available[,'Package']) {
        dbGetQuery(con, paste('INSERT OR REPLACE INTO packages (package,latest_r_version)'
                             ,'VALUES (',db_quote(package)
                             ,',',db_quote(available[package,'Version']),')'))
    }
    dbGetQuery(con,'DELETE FROM builds WHERE builds.package NOT IN (SELECT package FROM packages)')
    db_stop(con)
}

db_date_format <- '%Y-%m-%d'
db_time_format <- '%H:%M:%OS %Z'

db_record_build <- function(package, deb_version, log, success=F) {
    con <- db_start()
    o<-options(digits.secs = 6)
    dbGetQuery(con,paste('INSERT OR REPLACE INTO builds'
                        ,'(package,system,r_version,deb_epoch,deb_revision,db_version,success,date_stamp,time_stamp,scm_revision,log)'
                        ,'VALUES'
                        ,'(',db_quote(package)
                        ,',',db_quote(which_system)
                        ,',',db_quote(version_upstream(deb_version))
                        ,',',db_quote(version_epoch(deb_version))
                        ,',',db_quote(version_revision(deb_version))
                        ,',',db_cur_version(con)
                        ,',',as.integer(success)
                        ,',',db_quote(format(Sys.time(), db_date_format))
                        ,',',db_quote(format(Sys.time(), db_time_format))
                        ,',',db_quote(scm_revision)
                        ,',',db_quote(paste(log, collapse='\n'))
                        ,')'))
    options(o)
    db_stop(con)
}

db_builds <- function(pkgname) {
    # returns all successful builds
    con <- db_start()
    build <- dbGetQuery(con, paste('SELECT * FROM builds'
                       ,'WHERE success = 1'
                       ,'AND system =',db_quote(which_system)
                       ,'AND package =',db_quote(pkgname)))
    db_stop(con)
    if (length(build) == 0) {
        return(NULL)
    }
    return(db_cleanup_builds(build))
}

db_cleanup_builds <- function(build) {
    build$success <- as.logical(build$success)
    #o <-options(digits.secs = 6)
    dt <- as.POSIXct(strptime(paste(as.character(build[,"date_stamp"]), as.character(build[,"time_stamp"])),
                              paste(db_date_format, db_time_format)))
    build$time_stamp <- NULL
    build$date_stamp <- NULL
    newdf <- data.frame(build, date_stamp=dt)
    #print(newdf[, -grep("log", colnames(newdf))])
    #options(o)
    #print(newdf[, -grep("log", colnames(newdf))])
    return(newdf)
}

db_latest_build <- function(pkgname) {
    con <- db_start()
    build <- dbGetQuery(con, paste('SELECT * FROM builds'
                       ,'NATURAL JOIN (SELECT package,max(id) AS max_id FROM builds'
                       ,              'WHERE system =',db_quote(which_system)
                       ,              'GROUP BY package) AS last'
                       ,'WHERE id = max_id'
                       ,'AND builds.package =',db_quote(pkgname)))
    db_stop(con)
    if (length(build) == 0) {
        return(NULL)
    }
    return(db_cleanup_builds(build))
}

db_latest_build_version <- function(pkgname) {
    build <- db_latest_build(pkgname)
    if (is.null(build)) {
        return(NULL)
    }
    return(version_new(build$r_version, build$deb_revision, build$deb_epoch))
}

db_latest_build_status <- function(pkgname) {
    build <- db_latest_build(pkgname)
    if (is.null(build)) {
        return(NULL)
    }
    return(list(build$success,build$log))
}

db_outdated_packages <- function() {
    con <- db_start()
    packages <- dbGetQuery(con,paste('SELECT packages.package FROM packages'
               ,'LEFT OUTER JOIN ('
               # extract the latest attempt at building each package
               ,      'SELECT * FROM builds'
               ,      'NATURAL JOIN (SELECT package,max(id) AS max_id FROM builds'
               ,                    'WHERE system =',db_quote(which_system)
               ,                    'GROUP BY package) AS last'
               ,      'WHERE id = max_id) AS build'
               ,'ON build.package = packages.package'
               # outdated iff:
               # - there is no latest build
               ,'WHERE build.package IS NULL'
               # - the database has changed since last build
               ,'OR build.db_version < (SELECT max(version) FROM database_versions)'
               # - the debian epoch has been bumped up
               ,'OR build.deb_epoch < (SELECT max(base_epoch) FROM database_versions'
               ,                        'WHERE version IN ('
               ,                            'SELECT max(version) FROM database_versions))'
               # - the latest build is not of the latest R version
               ,'OR build.r_version != packages.latest_r_version'
               ))$package
    db_stop(con)
    return(packages)
}

db_blacklist_packages <- function() {
    con <- db_start()
    packages <- dbGetQuery(con,'SELECT package from blacklist_packages')$package
    db_stop(con)
    return(packages)
}
