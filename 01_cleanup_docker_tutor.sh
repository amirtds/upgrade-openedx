#! /bin/bash

# 1 Preparing the environment
## 1.1 If docker is already installed, stop all existing containers and remove all images, volumes, and networks
if ! command -v docker &> /dev/null; then
  echo "Docker is not installed. Please install Docker first."
  exit 1
fi

### Check if there are any running containers
if [ "$(docker ps -q)" ]; then
  docker stop $(docker ps -q)
fi

### Remove all containers
if [ "$(docker ps -a -q)" ]; then
  docker rm $(docker ps -a -q)
fi

## Remove all images
if [ "$(docker images -q)" ]; then
  docker rmi $(docker images -q)
fi

### Remove all volumes
if [ "$(docker volume ls -q)" ]; then
  docker volume rm $(docker volume ls -q)
fi



# Install Open edX Ironwood
tvm install v3.12.6
tvm project init ironwood v3.12.6
cd ironwood
source .tvm/bin/activate
tutor local quickstart -I

# wait until it is done 
# I, [2024-12-03T00:48:12.407079 #32]  INFO -- : Alias [content] now points to index [content_20241203004812209].
# I, [2024-12-03T00:48:12.419250 #32]  INFO -- : Catch up from 2024-12-03 00:43:12 UTC complete.
# I, [2024-12-03T00:48:12.419345 #32]  INFO -- : Rebuild index complete.
# All services initialised.
# The Open edX platform is now running in detached mode
# Your Open edX platform is ready and can be accessed at the following urls:

#     http://localhost
#     http://studio.localhost
#     http://www.myopenedx.com
#     http://studio.www.myopenedx.com