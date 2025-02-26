#!/bin/bash

basedir="${basedir}"
if [ "${basedir}" = "" ] ; then
	basedir="${PWD}/workdir"
	[[ -d "${basedir}" ]]  || mkdir -p "${basedir}"
fi

# Input artifact info
grouipId=$1
artifactId=$2
version=$3
source ./conf.sh

upload_local_repo="${basedir}/upload-local-repo/"

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

base_info(){
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
}

base_info

if [[ -d "${local_tmp_repo}" ]] ; then
	rm -r  "${local_tmp_repo}" || die "Failed to delete existing dir: $local_tmp_repo" ;
	mkdir "${local_tmp_repo}" ;
else
	mkdir "${local_tmp_repo}" || die "Unable to create directory: $local_tmp_repo"
fi




echo "Generate POM using dependency."
echo "--------------------------------------------------------------------------------"


sed -e "s/##GROUP_ID##/$grouipId/g"  -e "s/##ARTIFACT_ID##/$artifactId/g"  -e "s/##VERSION##/$version/g"  "pom-template.xml" | tee "${tmp_pom}"


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

	if [[ -e "${jar_file}" ]] && [[ -e "${pom_file}" ]] ; then
		echo "Jar and POM found for: $jar_file"
	else 
		echo "Jar has no corresponding POM, check manually: $jar_file"
		echo "TODO: Support for clasiffiers and types may fix this"
		echo "${jar_file}" >> "${fail_jarlist}"
		return 1;
	fi
	local target_parent_groupId=$(xpath -q -e '/project/parent/groupId/text()'  "${pom_file}")
	local target_parent_version=$(xpath -q -e '/project/parent/version/text()'  "${pom_file}")
	local target_groupId=$(xpath -q -e '/project/groupId/text()'  "${pom_file}")
	if [[ "${target_parent_groupId}" != "" ]] ; then
		target_groupId="${target_parent_groupId}"
	fi
	local target_artifactId=$(xpath -q -e '/project/artifactId/text()'   "${pom_file}")
	local target_version=$(xpath -q -e '/project/version/text()' "${pom_file}")
	if [[ "${target_version}" = "" ]]  && [[ "${target_parent_version}" != "" ]]   ; then 
		target_version="${target_parent_version}"
	fi
	local jar_repo_path="${target_groupId//./\/}/${target_artifactId}/${target_version}/${target_artifactId}-${target_version}.jar"

	echo "Checking SHA1 in remote and local"

	local relative_jar_path="${jar_file#|$local_tmp_repo/|}"
	local sha1_url="${TARGET_REPO_URL}/${jar_repo_path}.sha1"
	local sha1_local_file="${jar_file}.sha1"
	local remote_sha1=$( curl -k -s "${sha1_url}" )
	local local_sha1=$(  cat "${sha1_local_file}" )
	local present_in_target="no"

	if [ -n "${local_sha1}" ]  ; then  
		if  [ "${local_sha1}" = "${remote_sha1}" ] ; then
			present_in_target="yes"
		fi
	fi

	if [ "${present_in_target}" = "yes" ] ; then
		echo "${remote_sha1} ${relative_jar_path}" >> "${existing_jarlist}"
		echo "Already present in target: ${TARGET_REPO_URL}/${jar_repo_path}" 
		echo "Unlisting pom: ${pom_file}"
		grep -v -F "${pom_file}" "${tmp_pomlist}" > "${tmp_pomlist}"
	else
		echo "Deploying "
		echo "Jar: ${jar_file}"
		echo "POM: ${pom_file}"

		mvn  \
			-Dmaven.repo.local="${upload_local_repo}" \
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

		if [ $? -eq 0   ] ; then 
			echo "Unlisting pom: ${pom_file}"
			grep -v -F "${pom_file}" "${tmp_pomlist}" > "${tmp_pomlist}"
			echo "${local_sha1} ${relative_jar_path}" >> "${uploaded_jarlist}"
		else
			echo "Jar upload failed: ${jar_file}"
			echo "${local_sha1} ${relative_jar_path}" >> "${fail_jarlist}"
		fi
	fi
	echo "--------------------------------------------------------------------------------"
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

if [ -e "${existing_jarlist}" ] ; then 
	echo "--------------------------------------------------------------------------------"
	echo "Existing artifacts: $( wc -l ${existing_jarlist} )"
	echo "--------------------------------------------------------------------------------"
	cat "${existing_jarlist}"
fi

if [ -e "${uploaded_jarlist}" ] ; then 
	echo "--------------------------------------------------------------------------------"
	echo "Uploaded artifacts: $( wc -l ${uploaded_jarlist} )"
	echo "--------------------------------------------------------------------------------"
	cat "${uploaded_jarlist}"
fi
if [ -e "${fail_jarlist}" ] ; then 
	echo "--------------------------------------------------------------------------------"
	echo "Failed artifacts: $( wc -l ${fail_jarlist} )"
	echo "--------------------------------------------------------------------------------"
	cat "${fail_jarlist}"
fi
if [ -e "${tmp_pomlist}" ] ; then 
	echo "--------------------------------------------------------------------------------"
	echo "Pending POMs: $( wc -l ${tmp_pomlist} )"
	echo "--------------------------------------------------------------------------------"
	cat "${tmp_pomlist}"
fi
echo "--------------------------------------------------------------------------------"
base_info
