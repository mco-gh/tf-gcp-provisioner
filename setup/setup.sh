#set -x

export REGION=us-central1
export ZONE=us-central1-a
export IMG_FAMILY=common-cu113-notebooks
export MACH_TYPE=n1-standard-4
export SVCS="storage.googleapis.com          \
             bigquery.googleapis.com         \
             pubsub.googleapis.com           \
             aiplatform.googleapis.com       \
             dataflow.googleapis.com         \
             run.googleapis.com              \
             cloudfunctions.googleapis.com   \
             artifactregistry.googleapis.com \
             serviceusage.googleapis.com     \
             iam.googleapis.com              \
             notebooks.googleapis.com"
                 
# Enable cloud services.

FILE=projects
if [ "$1" != "" ]
then
    FILE=$1
fi

while read PROJ
do
    if [[ $PROJ = \#* ]]
    then
        echo "Skipping comment: $PROJ"
        continue
    fi 

    echo "Setting up project $PROJ"
    gcloud config set project $PROJ 

    for SVC in $SVCS
    do
        echo "Enabling service $SVC"
        gcloud services enable $SVC
    done

    #PROJ_NUM=`gcloud projects list --filter="$(gcloud config get-value project)" --format="value(PROJECT_NUMBER)"`
    #BUCKET_PROJ_NUM=`gsutil ls -Lb gs://$PROJ | grep projectNumber | uniq | awk -F\" '{print $4}'`
    EXISTING_BUCKET=`gsutil ls gs://$PROJ 2>/dev/null`
    if [ "$EXISTING_BUCKET" != "" ]
    then
        echo "Pre-owned bucket found for project $PROJ - deleting and recreating"
        echo "Deleting project cloud storage bucket"
        gsutil -m rm -r gs://$PROJ
    fi
    echo "Creating project cloud storage bucket"
    gsutil mb -l us-central1 gs://$PROJ >/dev/null 2>&1
    #gsutil uniformbucketlevelaccess set on gs://$PROJ
    echo "Storage bucket gs://$PROJ ownership confirmed and configured"

    # Copy files needed by datagen to project bucket
    gsutil -m cp -r gs://fraudfinderdemo/datagen gs://$PROJ

    # Delete, then create and configure Workbench instance.
    gcloud notebooks instances delete $PROJ --location=$ZONE
    echo "Creating workbench instance"
    gsutil cp notebook_config.sh gs://fraudfinder.app/setup/notebook_config.sh
    gsutil acl ch -u AllUsers:R gs://fraudfinder.app/setup/notebook_config.sh
    gcloud notebooks instances create $PROJ              \
        --project=$PROJ                                  \
        --vm-image-project=deeplearning-platform-release \
        --vm-image-family=$IMG_FAMILY                    \
        --machine-type=$MACH_TYPE                        \
        --location=$ZONE                                 \
        --post-startup-script=gs://fraudfinder.app/setup/notebook_config.sh
    bq rm -f $PROJ:tx.txlabels
    bq rm -f $PROJ:tx.tx
    bq rm -f $PROJ:tx.predictions
    bq rm -f $PROJ:tx
    bq mk --location=$REGION $PROJ:tx
    bq mk --location=$REGION --schema="TX_ID:STRING,TX_TS:TIMESTAMP,CUSTOMER_ID:STRING,TERMINAL_ID:STRING,TX_AMOUNT:NUMERIC" $PROJ:tx.tx
    bq mk --location=$REGION --schema="TX_ID:STRING,CARDPRESENT_HACKED:INTEGER,CARDNOTPRESENT_HACKED:INTEGER,TERMINAL_HACKED:INTEGER,TX_FRAUD:INTEGER" $PROJ:tx.txlabels
    bq mk --location=$REGION --schema="tx_amount:FLOAT,terminal_id:STRING,customer_id:STRING,customer_id_avg_amount_1day_window:FLOAT,customer_id_avg_amount_7day_window:FLOAT,customer_id_avg_amount_14day_window:FLOAT,customer_id_nb_tx_1day_window:INTEGER,customer_id_nb_tx_7day_window:INTEGER,customer_id_nb_tx_14day_window:INTEGER,terminal_id_nb_tx_1day_window:INTEGER,terminal_id_nb_tx_7day_window:INTEGER,terminal_id_nb_tx_14day_window:INTEGER,terminal_id_risk_1day_window:FLOAT,terminal_id_risk_7day_window:FLOAT,terminal_id_risk_14day_window:FLOAT,prediction:FLOAT,latency:FLOAT" $PROJ:tx.predictions
    bq cp -f fraudfinderdemo:tx.tx       $PROJ:tx.tx
    bq cp -f fraudfinderdemo:tx.txlabels $PROJ:tx.txlabels

    # Delete, then create the pubsub queue
    gcloud pubsub subscriptions delete ff-tx-sub
    gcloud pubsub topics delete ff-tx
    gcloud pubsub topics create ff-tx
    gcloud pubsub subscriptions create ff-tx-sub --topic ff-tx
done <$FILE

