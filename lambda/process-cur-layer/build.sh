#!/bin/bash
export WRKDIR=$(pwd)
export LYR_PDS_DIR="layer-process-cur"
        

# Building Python-pandas layer
cd ${WRKDIR}/${LYR_PDS_DIR}/
${WRKDIR}/${LYR_PDS_DIR}/build_layer.sh
zip -r ${WRKDIR}/../dist/python3-layers.zip .
rm -rf ${WRKDIR}/${LYR_PDS_DIR}/python/