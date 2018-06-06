## Things I did June 4-6
 
 - ran cran2deb update
 - ran cran2deb build tidyverse
	 - `stringi` has a license failure
	 - Installed `sqlitebrowser` so I can edit sqlite database without runining it
	 - Added `stringi` license
 - First package to build is "crayon"
 - I can't find the resulting package?
 - Built and added r-cran-crayon, but removed
 
## Commands to Remember
`dget -u http://localhost/cran2deb2/rep/pool/main/c/crayon/crayon_1.3.4-1cran1.dsc`
`sudo pdebuild -- --debbuildopts "-sa" --allow-untrusted --basetgz /var/cache/pbuilder/trusty-amd64-base.tgz --distribution trusty --architecture amd64 --buildresult ~/build_tests/builds/
`


## Script Idea
1. drab dsc file with `dget`.  Probably in a `src` directory
2. cd into source folder
3. Make adjustments as needed (see my scripts)
4. build with pbuilder: `sudo pdebuild -- --debbuildopts "-sa" --allow-untrusted --basetgz /var/cache/pbuilder/trusty-amd64-base.tgz --distribution trusty --architecture amd64 --buildresult ~/build_tests/builds/`
5.	Move to builds directory, add to aptly
6.	`aptly repo add debbuilder *.deb`
7.	`sudo aptly -skip-signing publish update trusty`
8.	`sudo pbuilder update --basetgz /var/cache/pbuilder/trusty-amd64-base.tgz`


## Questions to ask Dirk
- What about i386 vs amd64?
- How did you get trusty added on to the package?
- Do we need to specify which aptly repo (trusty,unstable) the package belongs.

