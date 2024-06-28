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
	local ending=`addResourceID $repo_id $resource_id`;
	formatURL $ending
}

# Hold onto current tty status to hide password input and re-enable input
stty_orig=$(stty -g)
trap "stty ${stty_orig}" EXIT

# Get User to run islandora_datastream_crud as
read -p "Islandora_Datastream_Crud User: " USER

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
dir=$(mkdir "${tmpdir}/EADs")

# Use drush and islandora_datastream_crud to get EADs
drush --root=/var/www/html/drupal7/ --user=$USER --uri=http://gamera.library.pitt.edu \
islandora_datastream_crud_fetch_pids \
--solr_query='RELS_EXT_hasModel_uri_ms:info\:fedora/islandora\:findingAidCModel' \
--pid_file=$tmpdir/eadpids.txt


drush islandora_datastream_crud_fetch_datastreams --user=$USER --pid_file=$tmpdir/eadpids.txt \
--dsid=EADS --datastreams_directory=$dir

# Curl to get Session ID
# response is a json object
response=$(curl -s -X POST -F password=$password `formatLoginURL`)

# Make sure user correctly loged in, else exit early
if containsError; then
	exit 1
fi

if containsSession; then
	session=$(getSessionID $response)
	echo $session
	while IFS= read -r line; do
		IFS='	'
		read -r resourceID repoID EADID <<< "$line"
		echo $resourceID
		echo $repoID
		echo $EADID >> "${tmpdir}/ead_ids.txt"
		#curl -s -H "X-ArchivesSpace-Session: $session" `formatEAD_URL $repoID $resourceID` > "${dir}/${resourceID}_EAD.xml"
	done < "$1"
	#curl -H "X-ArchivesSpace-Session: $SESSION" `formatEAD_URL
	exit 0
fi

exit 1