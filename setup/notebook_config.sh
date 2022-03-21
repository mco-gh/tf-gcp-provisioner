PKGS="git+https://github.com/googleapis/python-aiplatform.git@main      \
      google-api-python-client                                          \
      google-cloud-storage==1.32.0                                      \
      xgboost"

# Installing google-cloud-pipeline-components==0.1.6 and kfp==1.8.2 causes problem.

# others to install?
# auth2client
# dask
# distributed
# explainable_ai_sdk 
# google-auth-oauthlib
# google-auth-httplib2
# google-cloud-aiplatform==1.4.3
# pandarallel
# Pandas-gbq
# requests
# Tensorflow
# tensorflow_data_validation[visualization]

REPO="https://github.com/mco-gh/fraudfinder.git"

cd /home/jupyter

#sudo /opt/conda/bin/pip3 install wheel
for PKG in $PKGS
do
    /opt/conda/bin/pip3 install $PKG >>/tmp/install_log.txt 2>&1
done

# Save git clone and Cloud Run deploy scripts in user's home directory.


cat >/home/jupyter/init <<'EOF'
export REGION=us-central1

echo "adding roles to compute service account"
# Get the compute service account
SA=`gcloud iam service-accounts list | grep "Compute Engine" | awk '{print $(NF-1)}'`
PROJ=`gcloud config list | grep "^project" | awk '{print $3'}`
for role in run.admin storage.admin artifactregistry.admin
do
    echo "adding role $role..."
    gcloud projects add-iam-policy-binding $PROJ --member serviceAccount:$SA --role roles/$role
done

echo "cloning project github repo"
git clone https://github.com/mco-gh/fraudfinder.git

echo "installing pipeline packages"
pip3 install kfp==1.8.2 google-cloud-pipeline-components==0.1.6

echo "deploying project microservices"
for APP in datagen predict server web
do
  export DOCKER_IMG=gcr.io/fraudfinderdemo/ff-$APP
  gcloud run deploy "ff-$APP" \
         --image "$DOCKER_IMG" \
         --platform "managed"  \
         --region "$REGION"    \
         --memory 4G           \
         --allow-unauthenticated
done
EOF
chmod +x /home/jupyter/init
