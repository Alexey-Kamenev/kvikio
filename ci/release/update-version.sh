#!/bin/bash
# Copyright (c) 2022-2023, NVIDIA CORPORATION.
##########################
# KvikIO Version Updater #
##########################

## Usage
# bash update-version.sh <new_version>

# Format is YY.MM.PP - no leading 'v' or trailing 'a'
NEXT_FULL_TAG=$1

# Get current version
CURRENT_TAG=$(git tag --merged HEAD | grep -xE '^v.*' | sort --version-sort | tail -n 1 | tr -d 'v')
CURRENT_MAJOR=$(echo $CURRENT_TAG | awk '{split($0, a, "."); print a[1]}')
CURRENT_MINOR=$(echo $CURRENT_TAG | awk '{split($0, a, "."); print a[2]}')
CURRENT_PATCH=$(echo $CURRENT_TAG | awk '{split($0, a, "."); print a[3]}')
CURRENT_SHORT_TAG=${CURRENT_MAJOR}.${CURRENT_MINOR}

#Get <major>.<minor> for next version
NEXT_MAJOR=$(echo $NEXT_FULL_TAG | awk '{split($0, a, "."); print a[1]}')
NEXT_MINOR=$(echo $NEXT_FULL_TAG | awk '{split($0, a, "."); print a[2]}')
NEXT_SHORT_TAG=${NEXT_MAJOR}.${NEXT_MINOR}
NEXT_UCX_PY_VERSION="$(curl -sL https://version.gpuci.io/rapids/${NEXT_SHORT_TAG}).*"

# Need to distutils-normalize the original version
NEXT_SHORT_TAG_PEP440=$(python -c "from setuptools.extern import packaging; print(packaging.version.Version('${NEXT_SHORT_TAG}'))")

echo "Preparing release $CURRENT_TAG => $NEXT_FULL_TAG"

# Inplace sed replace; workaround for Linux and Mac
function sed_runner() {
    sed -i.bak ''"$1"'' $2 && rm -f ${2}.bak
}

# cpp update
sed_runner "/project(/,/)/s/VERSION.*/VERSION ${NEXT_FULL_TAG}/" cpp/CMakeLists.txt

# Python CMakeLists updates
sed_runner 's/set(kvikio_version.*)/set(kvikio_version '${NEXT_FULL_TAG}')/g' python/CMakeLists.txt

# Python __init__.py updates
sed_runner "s/__version__ = .*/__version__ = \"${NEXT_FULL_TAG}\"/g" python/kvikio/__init__.py
sed_runner "s/__version__ = .*/__version__ = \"${NEXT_FULL_TAG}\"/g" legate/legate_kvikio/__init__.py

# Python pyproject.toml updates
sed_runner "s/^version = .*/version = \"${NEXT_FULL_TAG}\"/g" python/pyproject.toml
sed_runner "s/^version = .*/version = \"${NEXT_FULL_TAG}\"/g" legate/pyproject.toml

# rapids-cmake version
sed_runner 's/'"branch-.*\/RAPIDS.cmake"'/'"branch-${NEXT_SHORT_TAG}\/RAPIDS.cmake"'/g' cpp/cmake/fetch_rapids.cmake

# cmake-format rapids-cmake definitions
sed_runner 's/'"branch-.*\/cmake-format-rapids-cmake.json"'/'"branch-${NEXT_SHORT_TAG}\/cmake-format-rapids-cmake.json"'/g' ci/checks/style.sh

# doxyfile update
sed_runner 's/PROJECT_NUMBER         = .*/PROJECT_NUMBER         = '${NEXT_FULL_TAG}'/g' cpp/doxygen/Doxyfile

# sphinx docs update
sed_runner 's/version = .*/version = '"'${NEXT_SHORT_TAG}'"'/g' docs/source/conf.py
sed_runner 's/release = .*/release = '"'${NEXT_FULL_TAG}'"'/g' docs/source/conf.py

DEPENDENCIES=(
  cudf
)
for DEP in "${DEPENDENCIES[@]}"; do
  for FILE in dependencies.yaml conda/environments/*.yaml; do
    sed_runner "/-.* ${DEP}==/ s/==.*/==${NEXT_SHORT_TAG_PEP440}.*/g" ${FILE}
  done
done

# CI files
for FILE in .github/workflows/*.yaml; do
  sed_runner "/shared-action-workflows/ s/@.*/@branch-${NEXT_SHORT_TAG}/g" "${FILE}"
done
sed_runner "s/RAPIDS_VERSION_NUMBER=\".*/RAPIDS_VERSION_NUMBER=\"${NEXT_SHORT_TAG}\"/g" ci/build_docs.sh

# .devcontainer files
find .devcontainer/ -type f -name devcontainer.json -print0 | while IFS= read -r -d '' filename; do
    sed_runner "s@rapidsai/devcontainers:[0-9.]*@rapidsai/devcontainers:${NEXT_FULL_TAG}@g" "${filename}"
    sed_runner "s@rapidsai/devcontainers/features/rapids-build-utils:[0-9.]*@rapidsai/devcontainers/features/rapids-build-utils:${NEXT_SHORT_TAG_PEP440}@" "${filename}"
done
