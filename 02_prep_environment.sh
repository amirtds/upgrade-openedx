# 1 Install required packages
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y python3 python3-pip libyaml-dev python3-venv

# 2. Create virtual environment
python3 -m venv venv
source venv/bin/activate
pip install --upgrade setuptools
pip install setuptools

# 3. Add Docker's official GPG key
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 4. Add Docker repository
echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. Install Docker
sudo apt-get update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose

# 6. Install TVM
pip install git+https://github.com/eduNEXT/tvm.git