#!/bin/bash
set -x

CONTAINER=rems14

FILE=$(sudo docker exec -u root -it $CONTAINER /bin/bash -c "cd /opt/rems/rems/utilities/diagnostic_utility && ./rems-diag-utility.sh | grep 'REMS Diagnostic data is available at' | sed 's/REMS Diagnostic data is available at //g'")

echo $FILE

sudo docker cp $CONTAINER:$FILE ~/Logs_such/

sudo docker exec -u root -it $CONTAINER /bin/bash -c "rm -rf $FILE"