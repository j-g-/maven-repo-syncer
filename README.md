# Maven Repo Sync Script

This script synchronizes artifacts between Maven repositories by resolving dependencies, validating checksums, and deploying artifacts to the target repository.

## Prerequisites

- Maven
- `xmllint` for XML processing
- `curl` for HTTP requests

## Usage

```bash
./maven-sync.sh <groupId> <artifactId> <version>
```

### Parameters

- `<groupId>`: The group ID of the Maven artifact.
- `<artifactId>`: The artifact ID of the Maven artifact.
- `<version>`: The version of the Maven artifact.

## Script Overview

1. **Setup**:
   - The script initializes paths and configuration files.
   - Loads configuration settings from `conf.sh`.

2. **Generate POM**:
   - Generates a temporary POM file based on the provided `groupId`, `artifactId`, and `version`.

3. **Download Dependencies**:
   - Uses Maven to download dependencies into a temporary local repository.

4. **Process JAR Files**:
   - Checks each JAR file for a corresponding POM file.
   - Validates MD5 and SHA1 checksums with remote values.
   - Deploys the artifact if checksums don't match or are missing.

5. **Upload Artifacts**:
   - Deploys valid artifacts to the target repository.
   - Logs the status of each artifact (uploaded, failed).

## Configuration

Ensure the following files and variables are properly configured:

- `conf.sh`: Contains repository URLs and Maven settings XML paths.
- `pom-template.xml`: A template POM file used to generate the temporary POM file.
- `SOURCE_REPO_URL`: URL of the source repository.
- `TARGET_REPO_URL`: URL of the target repository.
- `SOURCE_SETTINGS_XML`: Maven settings XML file for source repository.
- `TARGET_SETTINGS_XML`: Maven settings XML file for target repository.

## Example

```bash
./maven-sync.sh com.example my-artifact 1.0.0
```

## Notes

- The script assumes that the Maven repositories are accessible and that the network configuration allows for downloading and uploading artifacts.
- The `conf.sh` file should define variables for `SOURCE_REPO_URL`, `TARGET_REPO_URL`, `SOURCE_SETTINGS_XML`, and `TARGET_SETTINGS_XML`.

## Error Handling

- The script will exit with an error message if it fails to create directories, generate the POM file, or deploy artifacts.
- Check the `fail-jarlist-sync-<groupId>-<artifactId>-<version>.txt` file for a list of JAR files that failed to sync.

