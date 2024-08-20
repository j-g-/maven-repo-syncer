#!/bin/bash

basedir="${PWD}"

# Input artifact info
grouipId=$1
artifactId=$2
version=$3
source ./conf.sh

#TODO: Classifier and type support

# Die function
die(){
	echo "Error: $1";
	exit 1;
}


local_tmp_repo="${basedir}/repo-sync-[$grouipId]-[$artifactId]-[$version]"
tmp_pom="${basedir}/pom-sync-[$grouipId]-[$artifactId]-[$version].xml"
tmp_jarlist="${basedir}/jarlist-sync-[$grouipId]-[$artifactId]-[$version].txt"
fail_jarlist="${basedir}/fail-jarlist-sync-[$grouipId]-[$artifactId]-[$version].txt"
existing_jarlist="${basedir}/existing-jarlist-sync-[$grouipId]-[$artifactId]-[$version].txt"
uploaded_jarlist="${basedir}/uploaded-jarlist-sync-[$grouipId]-[$artifactId]-[$version].txt"
tmp_pomlist="${basedir}/pomlist-sync-[$grouipId]-[$artifactId]-[$version].txt"

cat << EOF
** Maven repo-sync **
--------------------------------------------------------------------------------
Trying sync for:
grouipId=$grouipId
artifactId=$artifactId
version=$version

From Repo: $SOURCE_REPO_URL
To Repo: $TARGET_REPO_URL
Local tmp repo: $local_tmp_repo
--------------------------------------------------------------------------------
EOF

if [[ -d "${local_tmp_repo}" ]] ; then
	rm -r  "${local_tmp_repo}" || die "Failed to delete existing dir: $local_tmp_repo" ;
	mkdir "${local_tmp_repo}" ;
fi

mkdir "./${local_tmp_repo}" || die "Unable to create directory: $local_tmp_repo"

echo "Generate POM using dependency."
echo "--------------------------------------------------------------------------------"


sed \ 
	-e "s/##GROUP_ID##/$grouipId/g" \
	-e "s/##ARTIFACT_ID##/$artifactId/g" \
	-e "s/##VERSION##/$version/g" "${basedir}/pom-template.xml" > "${tmp_pom}"


echo "--------------------------------------------------------------------------------"
cat "${tmp_pom}"
echo "--------------------------------------------------------------------------------"

echo "Download dependencies to: ${local_tmp_repo}"
echo "--------------------------------------------------------------------------------"

mvn \
	-Dmaven.repo.local="${local_tmp_repo}" \
	--settings "${SOURCE_SETTINGS_XML}" \
	--file "$tmp_pom" \
	dependency:resolve   

echo "--------------------------------------------------------------------------------"
echo "Creating Jar list:"
echo "--------------------------------------------------------------------------------"
find "${local_tmp_repo}" -name "*.jar" | tee "${tmp_jarlist}" 
find "${local_tmp_repo}" -name "*.pom" | tee "${tmp_pomlist}" 

jar_sync(){
	local jar_file=$1
	local pom_file="${jar_file%.jar}.pom"

	if [ -e "${jar_file}"] && [ -e "${pom_file}"] ; then
		echo "Jar and POM found for: $jar_file"
	else 
		echo "Jar has no corresponding POM, check manually: $jar_file"
		echo "TODO: Support for clasiffiers and types may fix this"
		echo "${jar_file}" >> "${fail_jarlist}"
		exit 1;
	fi

	echo "Checking MD5 and SHA1 in remote and local"

	local relative_jar_path="${jar_file#$local_tmp_repo/}"
	local md5_url="${TARGET_REPO_URL}/${relative_jar_path}.md5"
	local sha1_url="${TARGET_REPO_URL}/${relative_jar_path}.sha1"
	local md5_local_file="${jar_file}.md5"
	local sha1_local_file="${jar_file}.sha1"
	local remote_md5=$( curl -k -s "${md5_url}" )
	local remote_sha1=$( curl -k -s "${sha1_url}" )
	local local_md5=$(	[ -e "${md5_local_file}"  ] && cat "${local_md5}" )
	local local_sha1=$( [ -e "${sha1_local_file}" ] && cat "${local_sha1}" )
	local present_in_target="no"

	if [ -n "${local_md5}" ]  ; then  
		present_in_target=$( [ "${local_md5}" = "${remote_md5}" ] && echo "yes")
	fi

	if [ -n "${local_sha1}" ]  ; then  
		present_in_target=$( [ "${local_sha1}" = "${remote_sha1}" ] && echo "yes")
	fi

	if [ "${present_in_target}" = "yes" ] ; then
		echo "${jar_file}" >> "${existing_jarlist}"
		echo "Already present in target: ${jar_file}" 
	else
		echo "Deploying "
		echo "Jar: ${jar_file}"
		echo "POM: ${pom_file}"
		local target_groupId=$(xmllint --xpath 'string(//ns:groupId)' --xmlns=ns="http://maven.apache.org/POM/4.0.0" "${pom_file}")
		local target_artifactId=$(xmllint --xpath 'string(//ns:artifactId)' --xmlns=ns="http://maven.apache.org/POM/4.0.0" "${pom_file}")
		local target_version=$(xmllint --xpath 'string(//ns:version)' --xmlns=ns="http://maven.apache.org/POM/4.0.0" "${pom_file}")
		mvn \
		-Dmaven.repo.local="${local_tmp_repo}" \
		--settings "${TARGET_SETTINGS_XML}" \
		--file "${tmp_pom}" \
		-DrepositoryId="target-repo" \
		-Dfile="${jar_file}" \
		-Durl="${TARGET_REPO_URL}" \
		-DpomFile="${pom_file}" \
		-DgroupId="${target_groupId}" \
		-DartifactId="${target_artifactId}" \
		-Dversion="${target_version}" \
		deploy:deploy-file    
		if [ $? -q 0   ] ; then 
			sed -i "s/${pom_file}/d" "${tmp_pomlist}"
			echo "${jar_file}" >> "${uploaded_jarlist}"
		else
			echo "Jar upload failed: ${jar_file}"
			echo "${jar_file}" >> "${fail_jarlist}"
		fi
	fi
}



echo "--------------------------------------------------------------------------------"
echo "Upload artifacts to target repository: ${TARGET_REPO_URL}"
echo "--------------------------------------------------------------------------------"
for jar in $( cat "${tmp_jarlist}" ) ; do 
	jar_sync "${jar}"
done
echo "********************************************************************************"
echo "Summary"
echo "********************************************************************************"
echo "Uploaded"
echo "--------------------------------------------------------------------------------"
cat "${uploaded_jarlist}"
echo "--------------------------------------------------------------------------------"
echo "Failed"
echo "--------------------------------------------------------------------------------"
cat "${fail_jarlist}"
echo "--------------------------------------------------------------------------------"
echo "Pending POMs"
echo "--------------------------------------------------------------------------------"
cat "${tmp_pomlist}"
echo "--------------------------------------------------------------------------------"
