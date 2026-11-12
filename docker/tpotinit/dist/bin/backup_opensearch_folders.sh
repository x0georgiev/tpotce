#!/bin/bash

# Set vars
myDATE=$(date +%Y%m%d%H%M)
myPATH=$PWD
myOSPATH="data/opensearch/data"

# Backup OpenSearch
cd $HOME/tpotce

echo "### Now backing up OpenSearch folders ..."
tar cvfz $myPATH"/opensearch_"$myDATE".tgz" $myOSPATH

cd $myPATH
