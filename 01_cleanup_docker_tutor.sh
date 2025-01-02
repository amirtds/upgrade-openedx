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

## Remove all tutor data
if [ -d ~/.local/share/tutor ]; then
  sudo rm -rf ~/.local/share/tutor
fi

## Remove tutor executable
if [ -f /usr/local/bin/tutor ]; then
  sudo rm -f /usr/local/bin/tutor
fi
