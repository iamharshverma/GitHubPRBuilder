
#PR Builder for github : With Respect to every PR on a project it triggers a a Jenkins Test Suite and Allows to Merge or Reject PR
#!/bin/bash
set -e
echo "changing build name"
#echo $payload
#name="/tmp/payload_dir/"$BUILD_NUMBER
#echo "saving pay load to dir - "$name
#echo $payload > $name
prTitle=`echo $payload | jsawk 'return this.pull_request.title'`
prLabel=`echo $payload | jsawk 'return this.action'`
#prLabelName=`echo $payload | jsawk 'return this.label.name'`
echo "Pr Title is - "$prTitle
echo "Pr Label is - "$prLabel
JIRAID=`echo $prTitle | grep -Po "((?<!([A-Z])-[0-9])[A-Z]+-\d+)"`
if [  -z $JIRAID  ] ; then
    echo "#"$BUILD_NUMBER > /tmp/jiraId.txt
else
  echo "Jiraid is - "$JIRAID
  if [ "$prLabel" == "labeled" ] ; then
      prLabelName=`echo $payload | jsawk 'return this.label.name'`
    echo "Pr label is" $prLabelName
    echo "#"$BUILD_NUMBER" - "$JIRAID" - "$prLabelName > /tmp/jiraId.txt
  else
    echo "#"$BUILD_NUMBER" - "$JIRAID" - "$prLabel > /tmp/jiraId.txt
  fi
fi




#!/bin/bash
#first check if we should be running this or not
[ -f $WORKSPACE/.skipThis ] && sudo rm $WORKSPACE/.skipThis

touch $WORKSPACE/PRLinks

cause=`echo $payload | jsawk 'return this.action'`

ACTION=`echo $cause |grep -v "unlabeled" | grep "labeled"`
LABEL=`echo $payload | jq -r '.label.name'`
isMerged=`echo $payload | jsawk 'return this.pull_request.merged'`
echo "Action, Label and isMerged are - "$ACTION $LABEL $isMerged

token=`cat ~/.jiraToken`
gitToken=project_name-gitbot:`cat ~/.gitPassword`
gitURLToken=project_name-gitbot:`cat ~/.gitPasswordUrlEncode`

#####Getting Pr details
  #get the prtitle from the payload

  echo $payload > $WORKSPACE/payload.txt

  prTitle=`cat $WORKSPACE/payload.txt | jsawk 'return this.pull_request.title'`

  echo $prTitle > $WORKSPACE/prTitle.txt
  echo "Got prTitle - "$prTitle

  #check for prTitle having a jira
  JIRAID=`grep -Po "((?<!([A-Z])-[0-9])[A-Z]+-\d+)" $WORKSPACE/prTitle.txt`
  echo "Got JIRAID - "$JIRAID


  echo $JIRAID > $WORKSPACE/some.txt

  #get the jira ID from the ticket

  jira_json=`curl -X GET -H "Authorization: Basic $token" -H "Content-Type: application/json" "https://atlassian.net/rest/api/latest/issue/$JIRAID"`

  issueId=`echo $jira_json | jq -r '.id'`
  echo "Got issueId - "$issueId

  #get the jira details in a json

  jira_json=`curl -X GET -H "Authorization: Basic $token" -H "Content-Type: application/json" "https://atlassian.net/rest/dev-status/latest/issue/detail?issueId=$issueId&applicationType=github&dataType=branch"`

  echo "jira json is - "
  echo $jira_json

  pr=`echo $jira_json | jq -r '.detail' | jsawk 'return this.pullRequests' | jq '.[]' | jq '.[]' | jq -r '.url'`

  echo "pr found in jira is "$pr

  echo $pr > $WORKSPACE/PRLinks



#if [ $cause = '*opened' ] ; then
if  [ "$ACTION" == "labeled" ] && [ "$LABEL" == "TestRequest" ]
then
  #for jenkins to be able to merge branchs
  git config --global user.name "abc"
  git config --global user.email "abc@example.com"

  for dir in /opt/local/share/Docker/*
    do
        { # try
            cd ${dir}
            if [ -d .git ]; then
              echo "resetting to master for repo - "${dir##*/}
              git checkout master >/dev/null 2>&1
              git fetch https://$gitURLToken@github.com/project_name/${dir##*/}  master:new_master  >/dev/null 2>&1
              git checkout master >/dev/null 2>&1
              echo "resetting to master"
              git add -A
              git reset --hard new_master
              git branch -D new_master
              sudo rm -rf deploy
            fi
        } || { # catch
            echo "2.Successfully Caught"
        }
    done
  cd /opt/local/share/Docker

  #now read each line; goto the specified folder
  for p in $pr
  do
    #now checkout the PR
    prLink=`echo $p | awk -F '/' '{print $7}'`
    #set each PR into a pending state now
    repoOrg=`echo $p | awk -F '/' '{print $4}'`
    repoName=`echo $p | awk -F '/' '{print $5}'`
    PRId=`echo $p | awk -F '/' '{print $7}'`



    #get the PR status URL
    pr_details=`curl -X GET --user "$gitToken" -H "Content-Type: application/json" "https://api.github.com/repos/$repoOrg/$repoName/pulls/$PRId"`
    pr_state=`echo $pr_details | jsawk 'return this.state'`
    status_url=`echo $pr_details | jsawk 'return this.statuses_url'`
    [ "$pr_state" != "open" ] && continue

    echo "Merging PR - "$p

    curl "$status_url" \
      -H "Content-Type: application/json" \
      -X POST \
    --user "$gitToken" \
      -d "{\"state\": \"pending\", \"description\": \"project_name-Jenkins\", \"target_url\": \"$BUILD_URL\"}"

    #now goto the folder which this PR belongs to
    pr_dir=`echo $p | awk -F '/' '{print $5}'`
    cd $pr_dir

    #fetch and merge
    git fetch https://$gitURLToken@github.com/project_name/${pr_dir} pull/$prLink/head:pr-$prLink
    git checkout master  >/dev/null 2>&1
    git merge pr-$prLink
    git branch -D pr-$prLink
    cd /opt/local/share/Docker
  done


  echo "jiraID="$JIRAID > ${WORKSPACE}/jirainfo

else

    echo "Skipping Tests"

    if [ $isMerged == "true" ]
    then
        echo "Skipping futher actions as Pr is merged"
        touch $WORKSPACE/.skipThis
        exit 1;
    fi

    if [[ "$cause" == "opened" || "$cause" == "edited" || "$cause" == "closed" || "$cause" == "reopened" || "$cause" == "synchronize" ]]; then
        echo "Invalidating previous Reports"

        for p in $pr
        do
            repoOrg=`echo $p | awk -F '/' '{print $4}'`
            repoName=`echo $p | awk -F '/' '{print $5}'`
            PRId=`echo $p | awk -F '/' '{print $7}'`

            echo "PR Details are - "$repoOrg $repoName $PRId

            #get the PR status URL
            pr_details=`curl -X GET -u "$gitToken" -H "Content-Type: application/json" "https://api.github.com/repos/$repoOrg/$repoName/pulls/$PRId"`
            status_url=`echo $pr_details | jsawk 'return this.statuses_url'`

            issue_details=`curl -X GET -u "$gitToken" -H "Content-Type: application/json" "https://api.github.com/repos/$repoOrg/$repoName/issues/$PRId"`
            arr=($(echo $issue_details | jq ".labels" | jq ".[].name" | grep -v "Test"))
             VAR=""
             for i in "${arr[@]}"
             do
                VAR="$VAR $i"
             done
             VAR="${VAR//\"}"
             echo "Existing Tags"$VAR

             existing="{\"labels\": []}"
             if ! [ -z $VAR ]
             then
                 VAR=$(echo $VAR | sed -e 's/\(\w*\)/,"\1"/g' | cut -d , -f 2-)
                 existing="{\"labels\": [$VAR]}"
             fi

             curl -X POST -u "$gitToken" -H "Content-Type: application/json" https://api.github.com/repos/$repoOrg/$repoName/issues/$PRId -d "$existing"

             curl "$status_url" \
              -H "Content-Type: application/json" \
              -X POST \
              -u "$gitToken" \
              -d "{\"state\":\"failure\", \"description\": \"project_name-Jenkins\", \"target_url\": \"$BUILD_URL\",\"context\":\"tests\"}"
        done
    fi

    touch $WORKSPACE/.skipThis
    exit 1;

fi






#!/bin/bash
if [ -f $WORKSPACE/.skipThis ]; then

exit 0;

fi

#for jenkins to be able to execute files and checkout repos
echo "777 all shit"
sudo chmod -R 777 /opt/local/share

#cleanup
{ # try
   sudo rm -rf /opt/local/share/Docker/APIAutomation/ServerAutomation/target
   cd /opt/local/share/Docker/messaging-environment/messaging
   echo "Destroying Previous Env"
   sudo docker-compose down
   sudo docker stop $(sudo docker ps -a -q) ; sudo docker rm -f $(sudo docker ps -a -q)
   sudo docker volume prune -f
} || { # catch
    echo "1.Successfully Caught"
}

#Step 1: Bring up the data stores

#cd $WORKSPACE/messaging-environment/messaging

#docker-compose -f data-compose.yml up -d

#now wait till the entire gamut comes up - for science...

#sleep 120

#Step-2: Bring up the services now

sudo rm -rf /mnt/log/api/*

cd /opt/local/share/Docker/messaging-environment

sudo ./setup.sh
#| egrep -v "(^\[INFO\]|^\[DEBUG\])"

#wait for around 10 secs before kicking off bats

sleep 10

#populate cassandra

#cassandra=`docker ps -aqf "name=messaging_cassandra"`
#sudo docker exec $cassandra cqlsh -f /tmp/schema.cql

{ # try
   export BUILD_URL
   cd /opt/local/share/Docker/messaging-environment/jenkins/jobs/PR-Builder/
   sudo ./preBuild.sh
} || { # catch
    echo "Unable to perform preBuild tasks"
}


#Step 3 : Kick off bats and wait for it to finish

cd /opt/local/share/Docker/messaging-environment/messaging

{ # try
   sudo docker-compose -f bats.yml run --rm -e TEST_SCOPE=offline,infra -e EXPOSE_HTTP_SERVER=false runtest 2>&1 | grep "value - false" -B1
} || { # catch
    echo "Error Occured While Running Tests."
    sudo docker-compose -f bats.yml run --rm -e TEST_SCOPE=offline,infra -e EXPOSE_HTTP_SERVER=false runtest
}

echo "Results after 1st try"
Results=`cat /opt/local/share/Docker/Project_DIR/target/surefire-reports/testng-results.xml | grep "<testng-results skipped"`
echo $Results

total=`echo $Results | awk -F" " '{print $4;}'| awk -F"\"" '{print $2;}'`
passed=`echo $Results | awk -F" " '{print $5;}'| awk -F"\"" '{print $2;}'`

echo "Total - "$total", Passed - "$passed

if [ ! -z "$total" ] && [ ! -z "$passed" ] && [ $total = $passed ]; then
     echo "Skipping Second Time"
     exit 0
  else
     echo "Trying Second Time"
fi

{ # try
   sudo cp /opt/local/share/Docker/APIAutomation/ServerAutomation/target/surefire-reports/testng-results.xml /tmp/testng-results1.xml
   # cat /opt/local/share/Docker/APIAutomation/ServerAutomation/target/surefire-reports/testng-results.xml | grep 'status="FAIL"'
   sudo docker stop messaging_runtest_run_1

   sudo docker rm messaging_runtest_run_1
} || { # catch
    echo "Error Occured While Deleting Tests Container."
}

{ # try
   sudo docker-compose -f bats.yml run --rm -e TEST_SCOPE=offline,infra -e EXPOSE_HTTP_SERVER=false runtest 2>&1 | grep "value - false" -B1
} || { # catch
    echo "Error Occured While Running Tests."
}

echo "Results after 2st try"
Results=`cat /opt/local/share/Docker/Project_DIR/target/surefire-reports/testng-results.xml | grep "<testng-results skipped"`
echo $Results
