# USAGE: $0 [filename]
# filename: list of changed ASpace records on individual lines
# format for ASpace input is resourse id, repository id, and EAD id, whitespace separated.
# STDIN prompts:
# subdomain: pittsbapi or pittapi
# password: for sysdevapi

# Constants
SCHEME="https://"
ASPACE_LOGIN_URL=".as.atlas-sys.com/users/sysdevapi/login"
XML_FORMAT=".xml"

# Functions
# Functions
stringContain() { case $2 in *$1* ) return 0;; *) return 1;; esac ;}
containsSession() { stringContain "session" $response; }
containsError() { stringContain "error" $response; }

getSessionID() { 
	local hold=$(awk -F ',' '{print $1}' <<< $1);
	hold=$(awk -F ':' '{print $2}' <<< $hold);
	awk -F '"' '{print $2}' <<< $hold;
}

addRepoID() {
	ASPACE_REPOSITORIES=".as.atlas-sys.com/repositories/";
	ASPACE_RESOURCE_DESCRIPTION="/resource_descriptions/";
	local repo_id=$1
	local path="${ASPACE_REPOSITORIES}${repo_id}${ASPACE_RESOURCE_DESCRIPTION}";
	echo $path;
}

addResourceID() {
	local repo_id=$1
	local resource_id=$2
	local path=`addRepoID $repo_id`
	path="${path}${resource_id}${XML_FORMAT}"
	echo $path;
}

formatURL() {
	local ending=$1;
	local url="${SCHEME}${subDomain}${ending}";
	echo $url;
}

formatLoginURL() {
	formatURL $ASPACE_LOGIN_URL;
}

formatEAD_URL() {
	local repo_id=$1;
	local resource_id=$2;
	local ending=`addResourceID $repo_id $resource_id`'?include_unpublished=false&include_daos=true&numbered_cs=true&print_pdf=false&ead3=false';
	formatURL $ending
}

if [[ "$1" == "" ]]
then
  echo "Usage: $0 <filename>"
  echo "  filename: input file of EAD IDs"
  exit 1
fi

# Hold onto current tty status to hide password input and re-enable input
stty_orig=$(stty -g)
trap "stty ${stty_orig}" EXIT

# Get Subdomain for URL
read -p "subdomain: " subDomain

# Hide password
stty -echo
# Get Password
read -p "Password: " password

# Re-enable it
stty ${stty_orig}

echo ''

echo `formatLoginURL`

# Create temporary directory
tmpdir=$(mktemp -d)
workdir="${tmpdir}/EADs"
mkdir $workdir
updatedir="${tmpdir}/updates"
mkdir $updatedir

# Use drush and islandora_datastream_crud to get EADs
drush --root=/var/www/html/drupal7/ --user=$USER --uri=http://gamera.library.pitt.edu \
islandora_datastream_crud_fetch_pids \
--solr_query='RELS_EXT_hasModel_uri_ms:info\:fedora/islandora\:findingAidCModel' \
--pid_file=$tmpdir/eadpids.txt


drush -qy --root=/var/www/html/drupal7/ --user=$USER --uri=http://gamera.library.pitt.edu \
islandora_datastream_crud_fetch_datastreams --pid_file=$tmpdir/eadpids.txt \
--dsid=EAD --datastreams_directory=$workdir --filename_separator=^

# Curl to get Session ID
# response is a json object
response=$(curl -s -X POST -F password=$password `formatLoginURL`)

# Make sure user correctly loged in, else exit early
if containsError; then
	>&2 echo "ASpace Login Error: $response"
	exit 1
fi

if containsSession; then
	session=$(getSessionID $response)
	echo $session
	{
	read
	while IFS= read -r line; do
		IFS='	'
		read -r resourceID repoID EADID <<< "$line"
		updatedEAD=`grep -rl '>'$EADID'</eadid>' $workdir | grep -v -- '-test' | sed 's/EADs/updates/'`
		if [[ "$updatedEAD" ]]
		then
			wget -qO "$updatedEAD" --header "X-ArchivesSpace-Session: $session" "`formatEAD_URL $repoID $resourceID`"
		fi
	done
	} < "$1"
	for i in $updatedir/*.xml; do xmllint --noout $i; done
	echo drush -qy --root=/var/www/html/drupal7/ --user=$USER --uri=http://gamera.library.pitt.edu \
islandora_datastream_crud_push_datastreams \
--datastreams_source_directory=$updatedir --filename_separator=^ --no_derivs
	exit 0
fi

>&2 echo "No ASpace Session: $response"
exit 1
