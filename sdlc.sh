#!/usr/bin/env bash
set -Eeuo pipefail

#===============================================================================
# @Author: Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist
# @Description: SDLC automation script for IBM Bob operations
#===============================================================================

git pull origin main

chmod +x *.sh
chmod +x use-cases/*/*.sh
chmod +x patches/*/*.sh

git add -A 

git commit -m "Updated IBM Bob operations"

git push origin main


